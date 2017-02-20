Q = require 'q'
cheerio = require 'cheerio'
jsonfile = require 'jsonfile'
cloudscraper = require 'cloudscraper'

log = require './logging'

findIds = ->
  getPage = Q.denodeify(cloudscraper.get)
  getPage('http://currency.poe.trade')
  .then((data) ->
    $ = cheerio.load(data)
    currencies = $('#currency-want')
      .find('div[data-id]')
      .map((v) -> {
        name: $(v).attr('title'),
        id: $(v).data('id')
      }).get()
    console.dir(currencies)
    jsonfile.writeFileSync("#{__dirname}/../data/currency.json", currencies)
  ).catch(log.as.error)
    .done()

findIds()
