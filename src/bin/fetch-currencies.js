import { delay } from 'q';
import moment from 'moment';
import ntile from 'stats-percentile';
import { load } from 'cheerio';

import config from '../util/config';
import logging from '../util/logging';
import elastic from '../util/elastic';
import { scrape } from '../util/scraper';

const {
  static: { currencyPercentile }
} = config;

const { currency: log } = logging;

const getMetadata = async () => {
  const result = {
    currencies: [],
    leagues: []
  };
  // todo: needs to be rewritten to use official site
  const body = await scrape('http://currency.poe.trade');
  const $ = load(body);

  $('#currency-have')
    .find('.currency-square')
    .each((_, el) => {
      const $el = $(el);

      if (!($el.data('id') <= 27)) {
        return;
      }

      result.currencies.push({
        id: $el.data('id'),
        title: $el.attr('title')
      });
    });

  $('select[name="league"]')
    .find('option')
    .each((_, el) => {
      const $el = $(el);

      result.leagues.push($el.val());
    });

  // eslint-disable-next-line
  console.dir(result);

  return result;
};

const fetch = async (league, currency) => {
  await delay(Math.random() * 120000);

  log.info(`fetching ${currency.title} in ${league}`);

  try {
    // todo: needs to be rewritten to use official site
    const body = await scrape(
      `http://currency.poe.trade/search?league=${league}&online=x&want=${
        currency.id
      }&have=4`
    );
    const offers = [];
    const $ = load(body);

    $('div.displayoffer').each(el => {
      const $el = $(el);
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
    for (const currency of metadata.currencies) {
      // no need to await here since we want these to run in parallel
      fetch(league, currency);
    }
  }
};

fetchAll();
