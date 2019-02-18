import moment from 'moment';
import { promisify } from 'util';
import { prompt } from 'inquirer';
import { stat, readdir, unlink as rawUnlink } from 'fs';

import config from './config';
import logging from './logging';

const { cache: log } = logging;
const { retention: cacheConfig } = config.cache;

const statFile = promisify(stat);
const readDir = promisify(readdir);
const unlink = promisify(rawUnlink);

const retention = moment.duration(cacheConfig.interval, cacheConfig.unit);
const cutoff = moment().subtract(retention);
const cacheDir = `${__dirname}/../cache`;

const isStale = async changeId => {
  const path = `${cacheDir}/${changeId}`;
  const stats = await statFile(path);

  return moment(stats.birthtime).isBefore(cutoff);
};

const purgeCache = items => {
  for (const item of items) {
    const path = `${cacheDir}/${item}`;

    log.debug(path);
    unlink(path);
  }
};

const cleanCache = async () => {
  log.info(`cutoff is ${cutoff.toISOString()}`);
  try {
    const changeIds = await readDir(cacheDir);

    log.info(`${changeIds.length} total files in directory`);
    const toPurge = changeIds.filter(isStale);

    if (toPurge.length === 0) {
      return log.info('no cache markers need to be purged');
    }

    if (process.argv[2] === '-f') {
      purgeCache(toPurge);
      return log.info('forced cache purge');
    }

    const res = await prompt([
      {
        name: 'purge',
        type: 'confirm',
        default: false,
        options: [true, false],
        message: `${
          toPurge.length
        } cache markers that are older than ${retention.humanize()}`
      }
    ]);

    if (res && !res.purge) {
      return log.info('user requested exit');
    }

    if (!res || !res.purge) {
      return;
    }

    purgeCache(toPurge);
  } catch (err) {
    log.error(err);
  }
};

cleanCache();
