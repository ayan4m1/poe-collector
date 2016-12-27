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

export class League {
  id: String;
  description: String;
  url: String;
  start: Date;
  end: Date;
  constructor() { }
}

export class Listing {
  sellerAccount: String;
  sellerCharacter: String;
  stashId: Number;
  stashName: String;
  stashPosition: [Number, Number];
}

export class Item {
  uuid: String;
  listing: Listing;
  league: String;
  mods: Array<String>;
  itemType: String;
  itemBase: String;
  frameType: FrameType;
  constructor() { }

  public get fullName(): String {
    return this.itemType + ' ' + this.itemBase;
  };

  public get frameDesc(): String {
    for (let type in FrameType) {
      const x = parseInt(type, 10);
      // -1 means failure to parse
      if (x >= 0 && x === this.frameType.valueOf()) {
        return type;
      }
    }

    return 'Unknown';
  }
}
