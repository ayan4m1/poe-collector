'use strict'

fs = require 'fs'
jsonfile = require 'jsonfile'

log = require './logging'

path = "#{__dirname}/../data/ChaosEquivalencies.json"
chaosExists = fs.statSync(path)
return log.as.error('Did not find ChaosEquivalencies.json') unless chaosExists.isFile()

currencies = jsonfile.readFileSync(path)
regexes =
  bauble: /(Glassblower)?'?s?Bauble/i
  chisel: /(Cartographer)?'?s?Chis(el)?/i
  gcp: /(Gemcutter'?s?)?(Prism|gcp)/i
  jewelers: /Jew(eller)?'?s?(Orb)?/i
  chrome: /Chrom(atic)?(Orb)?/i
  fuse: /(Orb)?(of)?Fus(ing|e)?/i
  transmute: /(Orb)?(of)?Trans(mut(ation|e))?/i
  chance: /(Orb)?(of)?Chance/i
  alch: /(Orb)?(of)?Alch(emy)?/i
  regal: /Regal(Orb)?/i
  aug: /Orb(of)?Augmentation/i
  exalt: /Ex(alted)?(Orb)?/i
  alt: /Alt|(Orb)?(of)?Alteration/i
  chaos: /Chaos(Orb)?/i
  blessed: /Bless|Blessed(Orb)?/i
  divine: /Divine(Orb)?/i
  scour: /Scour|(Orb)?(of)?Scouring/i
  mirror: /Mir+(or)?(of)?(Kalandra)?/i
  regret: /(Orb)?(of)?Regret/i
  vaal: /Vaal(Orb)?/i
  eternal: /Eternal(Orb)?/i
  gold: /PerandusCoins?/i
  silver: /(Silver|Coin)+/i

module.exports =
  regexes: regexes
  values: currencies
