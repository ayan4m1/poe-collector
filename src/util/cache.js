import touch from 'touch';
import moment from 'moment';
import { promisify } from 'util';
import request from 'request-promise-native';
import { mkdir, unlink as rawUnlink, readdir, stat as rawStat } from 'fs';

import config from './config';
import logging from './logging';

const { cache: log } = logging;

const makeDir = promisify(mkdir);
const unlink = promisify(rawUnlink);
const readDir = promisify(readdir);
const stat = promisify(rawStat);

const cacheDir = `${__dirname}/${config.cache.cachePath}`;

const findLatestOnDisk = async () => {
  let items = await readDir(cacheDir);

  items = items.filter(async v => {
    const stats = await stat(`${cacheDir}/${v}`);

    return stats.isFile();
  });

  if (items.length === 0) {
    throw new Error('no cached files');
  }

  items.sort(async (a, b) => {
    const aStat = await stat(`${cacheDir}/${a}`).mtime.getTime();
    const bStat = await stat(`${cacheDir}/${b}`).mtime.getTime();

    return aStat - bStat;
  });

  const result = items.pop();

  log.info(`resuming from cache ${result}`);
  if (result) {
    return result;
  } else {
    throw new Error('time sorting of files failed');
  }
};

const findLatestFromWeb = async () => {
  log.debug('accessing poe.ninja API to find latest change');
  const res = await request({ uri: config.cache.latestChangeUrl });

  const stats = JSON.parse(res);
  const changeId = stats[config.cache.changeIdField];

  await touch(`${cacheDir}/${changeId}`);
  return changeId;
};

const findLatestChangeId = async () => {
  try {
    await makeDir(cacheDir);
  } catch (err) {
    log.warn(`cache directory ${cacheDir} already exists!`);
  }

  try {
    await findLatestOnDisk();
  } catch (err) {
    log.error(err);
    await findLatestFromWeb();
  }
};

const removeStaleCacheFiles = async () => {
  let removed = 0;
  const oldestToRetain = moment().subtract(
    config.cache.retention.interval,
    config.cache.retention.unit
  );
  const items = await readDir(cacheDir);

  for (const item of items) {
    const cachePath = `${cacheDir}/${item}`;
    const stats = await stat(cachePath);

    if (stats.isFile() && moment(stats.birthtime).isAfter(oldestToRetain)) {
      await unlink(cachePath);
      removed++;
    }
  }
  log.info(`removed ${removed} cache files`);
};

export default {
  findLatest: findLatestChangeId,
  removeStale: removeStaleCacheFiles
};
