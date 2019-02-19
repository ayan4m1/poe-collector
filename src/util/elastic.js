/* eslint-disable no-underscore-dangle, camelcase */
import moment from 'moment';
import { allSettled } from 'q';
import { Client } from 'elasticsearch';
import { readFileSync } from 'jsonfile';

import config from './config';
import parser from './parser';
import logging from './logging';

const { elastic: log } = logging;

const {
  elastic: { host, timeout, batchSize },
  log: { level: logLevel }
} = config;

let lastBufferCount = 0;

const createClient = () =>
  new Client({
    host,
    log: logLevel === 'debug' ? 'info' : 'error',
    requestTimeout: moment
      .duration(timeout.interval, timeout.unit)
      .asMilliseconds()
  });

let client = createClient();
const schema = readFileSync(`${__dirname}/../schema.json`);
const buffer = {
  stashes: [],
  listings: [],
  orphans: []
};

const createIndex = async name => {
  const params = { index: name };
  const exists = await client.indices.exists(params);

  if (exists) {
    return;
  }

  log.as.info(`creating index ${name}`);
  client.indices.create(params);
};

const putTemplate = async (name, settings, mappings) => {
  try {
    log.debug(`asked to create template ${name}`);
    await client.indices.putTemplate({
      create: false,
      name,
      body: {
        // eslint-disable-next-line camelcase
        index_patterns: [`${name}*`],
        settings,
        mappings
      }
    });

    log.info(`created template ${name}`);
  } catch (err) {
    log.error(err);
  }
};

const createDatedIndices = async (baseName, countDays) => {
  const tasks = [];

  for (let day = -1; day < countDays; day++) {
    const isoDate = moment()
      .add(day, 'day')
      .format('YYYY-MM-DD');

    createIndex(`${baseName}-${isoDate}`);
  }

  try {
    await Promise.all(tasks);
  } catch (err) {
    log.error(err);
  }
};

const pruneIndices = async (baseName, retention) => {
  const indices = await client.cat.indices({
    index: `poe-${baseName}*`,
    format: 'json',
    bytes: 'm'
  });

  const toRemove = [];
  const oldestToRetain = moment().subtract(retention.interval, retention.unit);

  for (const info of indices) {
    const { index, 'store.size': size } = info;
    const date = moment(index.substr(-10), 'YYYY-MM-DD');

    if (date.isBefore(oldestToRetain)) {
      toRemove.push(index);
      log.info(`removing ${index} with size ${size} MB`);
    } else {
      log.info(`keeping ${index} with size ${size} MB`);
    }
  }

  if (toRemove.length === 0) {
    return new Promise(resolve => resolve(toRemove));
  }

  try {
    await client.indices.delete({
      index: toRemove
    });

    log.info(`finished pruning ${toRemove.length} old indices`);
  } catch (err) {
    log.error(err);
  }
};

const updateIndices = async () => {
  const tasks = [];
  const templates = [];
  const { retention } = config.watcher;

  for (const [shard, info] of Object.entries(schema)) {
    const shardName = `poe-${shard}`;
    const { settings, mappings } = info;
    const retentionInfo = retention[shard];

    templates.push(putTemplate(shardName, settings, mappings));
    if (shard !== 'listing' && shard !== 'stash') {
      tasks.push(createIndex(shardName));
    } else {
      tasks.push(
        createDatedIndices(
          shardName,
          moment.duration(retentionInfo.interval, retentionInfo.unit).asDays()
        )
      );
    }
  }

  log.info(`putting ${templates.length} templates`);
  await Promise.all(templates);
  log.info(`running ${tasks.length} tasks`);
  await Promise.all(tasks);
};

const pruneAllIndices = async () => {
  const tasks = [];
  const { retention } = config.watcher;

  for (const type of ['stash', 'listing']) {
    tasks.push(pruneIndices(type, retention[type]));
  }

  log.info(`running ${tasks.length} prune tasks`);
  return await Promise.all(tasks);
};

const getShard = (type, date = moment()) =>
  `poe-${type}-${date.format('YYYY-MM-DD')}`;

const bulkDocuments = async bulk => {
  try {
    const docCount = bulk.length / 2;
    const startTime = process.hrtime();

    log.debug(`starting bulk of ${docCount} documents`);
    await client.bulk({ body: bulk });
    const bulkTime = moment.duration(
      startTime[0] + startTime[1] / 1e9,
      'seconds'
    );
    const bulkCount = Math.floor(docCount / bulkTime.asSeconds());

    log.info(`merged ${docCount} documents @ ${bulkCount} docs/sec`);
  } catch (err) {
    log.error(err);
  }
};

const orphanListings = async orphans => {
  const startTime = process.hrtime();
  const successful = result =>
    result.state === 'fulfilled' && result.value.updated > 0;

  try {
    const results = await allSettled(orphans);
    const durationMs = process.hrtime(startTime).asMilliseconds();

    const orphanCount = results
      .filter(successful)
      .reduce((prev, curr) => curr + prev.value.updated, 0);

    if (orphanCount > 0) {
      log.info(`orphaned ${orphanCount} documents in ${durationMs.toFixed(2)}`);
    }
  } catch (err) {
    log.error(err);
    if (err.displayName === 'RequestTimeout') {
      log.warn('re-creating elastic client due to request timeout!');
      client = createClient();
    }
  }
};

const orphanListing = async (stashId, itemIds) => {
  return await client.updateByQuery({
    index: 'poe-listing*',
    type: 'listing',
    requestsPerSecond: 1000,
    body: {
      script: {
        lang: 'painless',
        inline: 'ctx._source.removed=true;ctx._source.lastSeen=ctx._now;'
      },
      query: {
        bool: {
          must: [
            {
              term: {
                stash: stashId
              }
            },
            {
              term: {
                removed: false
              }
            }
          ],
          must_not: itemIds
        }
      }
    }
  });
};

const mergeStash = async (shard, stash) => {
  try {
    const res = await client.search({
      index: 'poe-stash*',
      type: 'stash',
      body: {
        query: {
          term: {
            _id: stash.id
          }
        }
      }
    });

    let verb = 'index';

    let listing = null;

    if (res.hits === null) {
      listing = {
        id: stash.id,
        name: stash.stash,
        lastSeen: moment().toDate(),
        owner: {
          account: stash.accountName,
          character: stash.lastCharacterName
        }
      };
    } else if (res.hits.total > 0) {
      verb = 'update';
      listing = res.hits.hits[0]._source;
      listing.name = stash.stash;
      listing.lastSeen = moment().toDate();
      listing.owner.character = stash.lastCharacterName;
      if (res.hits.total > 1) {
        const misplacedHits = res.hits.hits.filter(hit => hit._index === shard);

        for (const hit of misplacedHits) {
          buffer.orphans.push(
            client.delete({
              index: hit._index,
              type: 'stash',
              id: stash.id
            })
          );
        }

        const lastHit = misplacedHits[misplacedHits.length - 1];

        log.debug(
          `culling ${misplacedHits.length} old copies of stash ${lastHit._id}`
        );
      }
    }

    const header = {
      [verb]: {
        _index: shard,
        _type: 'stash',
        _id: stash.id
      }
    };
    const payload =
      verb === 'update'
        ? {
            doc: listing
          }
        : listing;

    buffer.stashes.push(header, payload);
  } catch (err) {
    log.error(err);
  }
};

const appendPayload = (verb, shard, listing) => {
  try {
    const header = {
      [verb]: {
        _index: shard,
        _type: 'listing',
        _id: listing.id
      }
    };

    let payload = listing;

    if (verb === 'update') {
      payload = {
        doc: payload
      };
    }

    return buffer.listings.push(header, payload);
  } catch (err) {
    log.error(err);
  }
};

const mergeListings = async (shard, items) => {
  try {
    const ids = Object.keys(items);
    const res = await client.search({
      index: 'poe-listing*',
      type: 'listing',
      size: ids.length,
      body: {
        query: {
          ids: {
            values: ids
          }
        }
      }
    });

    const { hits } = res.hits;

    if (res.hits.total > 0) {
      log.silly(`${ids.length} item listings queried, ${hits.length} returned`);

      for (const hit of hits) {
        const listing = hit._source;

        if (hit._index !== shard) {
          log.silly(`moving ${hit._id} up from ${hit._index}`);
          buffer.orphans.push(
            client.delete({
              index: hit._index,
              type: 'listing',
              id: hit._id
            })
          );
        } else {
          appendPayload('update', shard, parser.existing(hit, listing));
        }
      }

      for (const item of items) {
        appendPayload('index', shard, parser.new(item));
      }
    }
  } catch (err) {
    log.error(err);
  }
};

const mergeStashes = async stashes => {
  const shard = getShard('stash');
  const listingShard = getShard('listing');
  const isPremium = stash => stash && stash.stashType === 'PremiumTab';

  for (const stash of stashes.filter(isPremium)) {
    const ids = [];
    const items = {};

    await mergeStash(shard, stash);

    for (const item of stash.items) {
      item.stash = item.stash || stash.id;
      items[item.id] = item;
      ids.push({
        term: {
          id: item.id
        }
      });
    }

    buffer.orphans.push(orphanListing(stash.id, ids));
    try {
      await mergeListings(listingShard, items);
    } catch (err) {
      log.error(err);
    }

    const docCount = buffer.listings.length / 2;
    const fill = docCount / batchSize;

    if (fill > lastBufferCount + 0.1 && docCount <= batchSize) {
      log.as.debug(`buffer is ${(fill * 100).toFixed(1)}% full`);
      lastBufferCount = fill;
    }

    if (!(docCount > batchSize)) {
      return;
    }

    const stashCount = buffer.stashes.length / 2;

    log.debug(`flushing ${docCount} listings across ${stashCount} stashes`);
    const slicedBuf = buffer.listings.slice();
    const slicedOrphans = buffer.orphans.slice();

    Array.prototype.push.apply(slicedBuf, slicedBuf.stashes);
    buffer.listings.length = buffer.stashes.length = buffer.orphans.length = 0;
    lastBufferCount = 0;

    await bulkDocuments(slicedBuf);
    await orphanListings(slicedOrphans);
  }
};

const logFetch = async (changeId, fileSizeKb, downloadTimeMs) => {
  try {
    await client.index({
      id: changeId,
      type: 'fetch',
      index: 'poe-fetches',
      body: {
        fileSizeKb,
        downloadTimeMs,
        timestamp: moment.toDate()
      }
    });
  } catch (err) {
    log.error(err);
  }
};

export default {
  config: config.elastic,
  client,
  schema,
  updateIndices,
  pruneAllIndices,
  mergeStashes,
  logFetch
};
