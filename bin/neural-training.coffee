config = require('konfig')()

jsonfile = require 'jsonfile'
jsonpath = require 'jsonpath'
synaptic = require 'synaptic'

Architect = synaptic.Architect

features =
  life: '$.stats.life.*'
  mana: '$.stats.mana.*'
  shield: '$.defense.shield.*'
  armour: '$.defense.armour.*'
  evasion: '$.defense.evasion.*'
  moveSpeed: '$.stats.movementSpeed'
  eleResistances: '$.defense.resist.elemental.*'
  chaosResistance: '$.defense.resist.chaos'
  damage: '$.offense.damage.all'
  eleDamage: '$.offense.damage.elemental.*'
  block: '$.defense.blockChance.*'

sum = (paths) ->
  res = 0
  for path in paths
    temp = jsonpath.query(path)
    temp = temp ? 0
    res += res.flat * (1 + res.percent)
  res

outputs =
  highLife: (inputs) ->
    res = jsonpath.query(inputs, features.life)
    console.dir(res)
    return 0

perceptron = new Architect.Perceptron(2, 2, 2)

data = jsonfile.readFileSync("#{__dirname}/../data/Gear.json")

bias = {}
for key, val of data.stats
  for tier in val.tiers
    bias[key] = Math.max(bias[key] ? 0, tier.ideal)

perceptron.trainer.train(data.stats, {
  rate: 0.2
  iterations: 100
  error: 0.1
  shuffle: true
  log: 1
  cost: synaptic.Trainer.cost.CROSS_ENTROPY()
})

console.dir(perceptron)
