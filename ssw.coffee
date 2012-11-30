# ----------------------------------------------------------------
# sqs thing
#
# also tries to estimate when a queue might drain
# ----------------------------------------------------------------


aws          = require "aws-lib"
_            = require "underscore"
async        = require "async"
term         = require "node-term-ui"
timethat     = require "timethat"
stringformat = require "stringformat"

{ key, secret } = require "./aws-keys"

poll_interval = 0


# ------------------------------
# some helpers
# ------------------------------

new_sqs_client = (options = null) -> aws.createSQSClient key, secret, options
strip_path = (path) -> path.replace "https://sqs.us-east-1.amazonaws.com", ""
stringformat.extendString "format"


# ------------------------------
# keep history of queue details
# ------------------------------

history            = []
max_history_length = 200

add_to_history = (obj) ->

  history.push
    time: Date.now()
    obj: obj

  if history.length > max_history_length
    history = history.slice history.length - max_history_length

latest_from_history = -> _.last(history)?.obj



# ---------------------------------------
# use regression lines to estimate when
# a queue will drain
# ---------------------------------------

estimate_time_when_y_zero = (set) ->

  n = set.length

  r = (fn) -> _.reduce set, fn, 0

  sums =
    y: r (a, b) -> a + b.y
    x: r (a, b) -> a + b.x
    xy: r (a, b) -> a + (b.x * b.y)
    x2: r (a, b) -> a + (b.x * b.x)

  slope = (n * sums.xy - (sums.x * sums.y)) / (n * sums.x2 - (sums.x * sums.x))
  intercept = (sums.y - (slope * sums.x)) / n

  (0 - intercept) / slope




get_data_set_by_queue_name = (queue_name) ->
  _.map history, (q) -> 
    current_queue = _.filter q.obj, (i) -> i.queue_name == queue_name
    { x: q.time, y: current_queue[0].available + current_queue[0].in_flight }






# ------------------------------
# printing
# ------------------------------


reset_screen = -> do term.clear; do term.home

print_results = ->

  do reset_screen
  for queue_detail, idx in latest_from_history()
    drain_message = ""

    if queue_detail.available > 1
      queue_data_set = get_data_set_by_queue_name queue_detail.queue_name

      if queue_data_set.length > 1
        estimated_time = estimate_time_when_y_zero(queue_data_set)
        if (not isNaN estimated_time) and _.isFinite(estimated_time) and estimated_time > Date.now()
          drain_message = "estimated drain in #{timethat.calc Date.now(), new Date(Math.floor estimated_time)}"

    out_str = "{0:-30} {1:10i} {2:10i} {3}".format queue_detail.queue_name, queue_detail.available, queue_detail.in_flight, drain_message
    console.log out_str


# ------------------------------
# sqs functions, get queues aval
# and getting details of them
# ------------------------------

get_queue_paths = (callback) ->

  sqs = do new_sqs_client
  sqs.call "ListQueues", {}, (err, result) ->
    callback result.ListQueuesResult.QueueUrl


# callback will pass through an object: { queue_name, available, in_flight }

get_details = (path, callback) ->

  stripped_path = strip_path path
  sqs = new_sqs_client
    path: stripped_path

  options =
    "AttributeName.1": "ApproximateNumberOfMessages"
    "AttributeName.2": "ApproximateNumberOfMessagesNotVisible"

  sqs.call "GetQueueAttributes", options, (err, result) ->

    get_attribute = (name) ->
      for attr in result.GetQueueAttributesResult.Attribute
        return attr.Value if attr.Name == name
      null

    callback_args =
      queue_name: _.last stripped_path.split("/")
      available: parseInt get_attribute("ApproximateNumberOfMessages"), 10
      in_flight: parseInt get_attribute("ApproximateNumberOfMessagesNotVisible"), 10

    callback null, callback_args





# ----------------
# start things off
# ----------------

do reset_screen
get_queue_paths (paths) ->

  process_queues = ->
    async.map paths, get_details, (err, results) ->
      add_to_history _.sortBy results, "queue_name"
      do print_results

      setTimeout process_queues, poll_interval

  do process_queues

