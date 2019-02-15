import cosmiconfig from 'cosmiconfig';

/* eslint-disable no-sync */
const configSearch = cosmiconfig('exile').searchSync();

if (configSearch === null) {
  throw new Error(
    'Did not find a config file for module name "exile" - see https://github.com/davidtheclark/cosmiconfig#explorersearch'
  );
}

export default configSearch.config;
