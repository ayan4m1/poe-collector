import { delay } from 'q';
import moment from 'moment';
import cheerio from 'cheerio';
import ntile from 'stats-percentile';
import cloudscraper from 'cloudscraper';

import config from '../util/config';
import logging from '../util/logging';
import elastic from '../util/elastic';

const {
  static: { currencyPercentile }
} = config;

const { currency: log } = logging;

const getMetadata = async () => {};

const fetch = async (league, currency) => {
  await delay(Math.random() * 120000);

  log.info(`fetching ${currency.title} in ${league}`);

  try {
    // todo: needs to be rewritten to use official site
    const [, body] = await cloudscraper.get(
      `http://currency.poe.trade/search?league=${league}&online=x&want=${
        currency.id
      }&have=4`
    );

    const offers = [];
    const $ = cheerio.load(body);

    $('div.displayoffer').each($el => {
      const sell = parseFloat($el.data('sellvalue'));
      const buy = parseFloat($el.data('buyvalue'));
      const rate = buy / sell;

      offers.push(rate);
    });

    const total = (ntile(offers, currencyPercentile) || 0).toFixed(2);

    log.info(`${currency.title} averages ${total} chaos`);

    await elastic.client.index({
      index: 'poe-currency',
      type: 'trade',
      id: `${league}-${currency.title}-${moment().valueOf()}`,
      body: {
        league,
        name: currency.title,
        chaos: parseFloat(total),
        timestamp: moment().toDate()
      }
    });

    log.debug('Indexed currency offer');
  } catch (err) {
    log.error(err);
  }
};

const fetchAll = async () => {
  const metadata = await getMetadata();

  for (const league of metadata.leagues) {
    for (const currency of league.currencies) {
      // no need to await here since we want these to run in parallel
      fetch(league, currency);
    }
  }
};

fetchAll();
