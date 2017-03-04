#!/usr/bin/env bash

RETAIN_MINS=1
PURGE_COUNT=$(find ./cache/* -mmin +${RETAIN_MINS} | wc -l)

if [ $PURGE_COUNT -le 0 ]
then
  echo "Did not find any files older than ${RETAIN_MINS} minutes"
  exit 1
fi

read -p "$PURGE_COUNT files will be removed, are you SURE?! " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
  find ./cache/* -mmin +${RETAIN_MINS} -exec echo {} \; -exec rm {} \;
fi

exit 0
