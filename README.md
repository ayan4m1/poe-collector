# PoE Notifier

## Setup

Obligatory first step:

> npm install

You must extract the following data from the Path of Exile client. Don't violate their Terms of Use, no warranty, etc:

* GemTags
* Mods
* ModType
* Stats
* Tags

These should all be CSV files placed in the `./poe-notifier/data` directory. How to create these files is outside the scope of this project.

Run `coffee bin/fetch-data-static.coffee` to convert these files into JSON which is used elsewhere in the application.

## Usage

> TODO

Build the web interface with:

> gulp

Start the web interface with:

> gulp serve

## Indexing

Run `forever -c coffee bin/start-watcher.coffee` from the `./poe-notifier` directory.

This will follow the "river" of data coming from GGG and dump it to the configured Elastic node.

The batch size and timeout may need tuning in `config/elastic.yaml`

### To update static data (e.g. after game update)

> Update CSV files in `./poe-notifier/data`

> coffee bin/fetch-base-types-web.coffee

> coffee bin/fetch-data-static.coffee

> coffee bin/fetch-leagues-web.coffee

## Scheduling

Indices must be created ahead of time and should be pruned after a certain retention period. The config YAML allows you to customize all of this.

There is an example crontab provided that shows how to automate the system.

## Contributing

> TODO
