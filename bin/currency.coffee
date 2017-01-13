module.exports =
  regexes:
    bauble: /(Glassblower)?'?s?Bauble/i
    chisel: /(Cartographer)?'?s?Chis(el)?/i
    gcp: /(Gemcutter'?s?)?(Prism|gpc)/i
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
    chaos: /Ch?(aos)?(Orb)?/i
    blessed: /Bless|Blessed(Orb)?/i
    divine: /Divine(Orb)?/i
    scour: /Scour|(Orb)?(of)?Scouring/i
    mirror: /Mir+(or)?(of)?(Kalandra)?/i
    regret: /(Orb)?(of)?Regret/i
    vaal: /Vaal(Orb)?/i
    eternal: /Eternal(Orb)?/i
    gold: /PerandusCoins?/i
    silver: /(Silver|Coin)+/i
  values:
    # < 1 chaos, fluctuates
    blessed: 1 / 3
    chisel: 1 / 3
    chrome: 1 / 12
    alt: 1 / 10
    fuse: 1 / 2
    alch: 1 / 2
    scour: 1 / 2
    # chaos-equivalent
    chaos: 1
    vaal: 1
    regret: 1
    regal: 1
    # > 1 chaos
    divine: 10
    exalt: 70
    # these are silly
    eternal: 10000
    mirror: 5000
