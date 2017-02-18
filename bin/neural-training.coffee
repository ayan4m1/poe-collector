synaptic = require 'synaptic'

perceptron = new Architect.Perceptron(2, 7, 1)
trainer = new Trainer()

layers:
  defense: new Layer(1)
  meleeOffense: new Layer()
  casterOffense: new Layer()
  rangedOffense: new Layer()
  chaosInnoculation: new Layer()
