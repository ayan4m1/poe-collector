import config from './config';

import { Container, format, transports } from 'winston';
const { combine, colorize, label, prettyPrint, printf, timestamp } = format;

const loggers = {};
const container = new Container();
const categories = {
  cache: 'cache',
  currency: 'currency',
  elastic: 'es',
  parser: 'parse',
  pipeline: 'pipe'
};

for (const [category, categoryLabel] of Object.entries(categories)) {
  let formatter = data => `[${data.level}][${data.label}] ${data.message}`;
  const formatters = [label({ label: categoryLabel })];

  if (config.logging.colorize) {
    formatters.push(colorize());
  }

  if (config.logging.timestamp !== false) {
    formatters.push(timestamp({ format: config.logging.timestamp }));
    formatter = data =>
      `${data.timestamp} [${data.level}][${data.label}] ${data.message}`;
  }

  formatters.push(prettyPrint(), printf(formatter));
  container.add(category, {
    transports: [
      new transports.Console({
        format: combine.apply(null, formatters)
      }),
      new transports.DailyRotateFile({
        filename: 'log/%DATE%.log'
      })
    ]
  });

  loggers[category] = container.get(category);
}

export default loggers;
