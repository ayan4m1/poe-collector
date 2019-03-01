/* eslint-disable no-underscore-dangle */
import config from './config';
import elastic from './elastic';
import logging from './logging';

const { currency: log } = logging;
const {
  static: { leagues }
} = config;

const fetchValue = async league => {
  try {
    const res = await elastic.client.search({
      index: 'poe-currency',
      body: {
        query: {
          term: {
            league
          }
        },
        size: 1000,
        sort: {
          timestamp: {
            order: 'desc'
          }
        }
      }
    });

    const values = {};
    const existing = [];

    values[league] = {};

    const validListing = hit => {
      const listing = hit._source;

      if (existing.indexOf(listing.name) !== -1) {
        return false;
      }

      if (listing.name === 'Chaos Orb') {
        values[league]['Chaos Orb'] = 1;
        return false;
      }

      return true;
    };

    for (const hit of res.hits.hits.filter(validListing)) {
      const listing = hit._source;

      values[league][listing.name] = listing.chaos;
      existing.push(listing.name);
    }

    return values;
  } catch (err) {
    log.error(err);
  }
};

const fetchValues = async () => {
  const tasks = [];

  for (const league of leagues) {
    tasks.push(fetchValue(league));
  }

  try {
    const result = {};
    const results = await Promise.all(tasks);

    for (const value of results) {
      Object.assign(result, value);
    }

    return result;
  } catch (err) {
    log.error(err);
  }
};

export default {
  fetchValues
};
