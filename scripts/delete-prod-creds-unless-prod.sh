#!/bin/bash

if [ "$CONFIG" != "prod" ]; then
  rm -rf credential/
  rm -rf config/main.prod.coffee
fi