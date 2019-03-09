import elastic from 'util/elastic';
import logging from 'util/logging';

const { indices: log } = logging;

elastic
  .pruneAllIndices()
  .then(() => {
    log.info('removed stale indices');
  })
  .catch(log.error);
