export class SellerInfo {
  account: String;
  character: String;
}

export enum FrameType {
  Normal = 0,
  Magic = 1,
  Rare = 2,
  Unique = 3,
  Gem = 4,
  Currency = 5,
  DivinationCard = 6,
  QuestItem = 7,
  Prophecy = 8
}

export class DamageRange {
  min: Number;
  max: Number;
  constructor(min: Number, max: Number) {
    this.min = min;
    this.max = max;
  }
  get toString(): String {
    return this.min + ' ' + this.max;
  }
}

export interface StashLocation {
  x: Number;
  y: Number;
  width: Number;
  height: Number;
}

export interface SocketInfo {
  red: Number;
  green: Number;
  blue: Number;
  white: Number;
  links: Array<Array<Number>>;
}

export interface OffenseInfo {
  elemental: ElementalDamageInfo;
  physical: DamageRange;
  chaos: DamageRange;
}

export class ElementalDamageInfo {
  fire: DamageRange;
  lightning: DamageRange;
  cold: DamageRange;
}

export class ElementalResistanceInfo {
  fire: Number;
  lightning: Number;
  cold: Number;
}

export class ResistanceInfo {
  elemental: ElementalResistanceInfo;
  chaos: Number;
}

export class DefenseInfo {
  resistance: ResistanceInfo;
  armour: Number;
  evasion: Number;
  shield: Number;
}

export class StackInfo {
  count: Number;
  maximum: Number;
}

export class League {
  id: String;
  description: String;
  url: String;
  start: Date;
  end: Date;
  constructor() { }
}

export class Stash {
  id: String;
  league: String;
  name: String;
  lastSeen: Date;
  seller: SellerInfo;
}

export class Listing {
  stash: Stash;
  id: String;
  _parent: String;
  league: String;
  name: String;
  fullName: String;
  typeLine: String;
  baseLine: String;
  gearType: String;
  rarity: String;
  location: StashLocation;
  sockets: SocketInfo;
  modifiers: Array<String>;
  offense: OffenseInfo;
  defense: DefenseInfo;
  note: String;
  level: Number;
  identified: Boolean;
  corrupted: Boolean;
  locked: Boolean;
  frame: Number;
  price: Number;
  chaosPrice: Number;
  stack: StackInfo;
  lastSeen: Date;
  firstSeen: Date;
  removed: Boolean;
}
