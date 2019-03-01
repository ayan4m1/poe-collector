import { promisify } from 'util';
import { gunzip as rawGunzip } from 'zlib';
import { get as rawGet } from 'cloudscraper';

const gunzip = promisify(rawGunzip);
const get = promisify(rawGet);

export const scrape = async url => {
  const res = await get(url);

  if (res.headers['content-encoding'] === 'gzip') {
    return await gunzip(res.body);
  } else {
    return res.body;
  }
};
