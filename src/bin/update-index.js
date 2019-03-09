import elastic from 'util/elastic';
import logging from 'util/logging';

const { indices: log } = logging;

elastic
  .updateIndices()
  .then(() => {
    log.info('finished updating elastic indices');
  })
  .catch(log.error);
