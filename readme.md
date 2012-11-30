# Simple SQS watcher

## Install

install dependencies

    npm i

Copy aws key sample file

    cp aws-keys-sample.coffee aws-keys.coffee

Insert your aws keys into aws-keys.coffee

Run!

    coffee ssw.coffee

## Output

This will get all queues in your account and start watching the messages available and how many are in flight.

## Estimates

Uses regression analysis to estimate when a queue will drain (have 0 messages available). Currently it keeps a sample size of up to 200 data points.
