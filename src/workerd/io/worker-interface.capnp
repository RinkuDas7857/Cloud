# Copyright (c) 2017-2022 Cloudflare, Inc.
# Licensed under the Apache 2.0 license found in the LICENSE file or at:
#     https://opensource.org/licenses/Apache-2.0

@0xf7958855f6746344;

using Cxx = import "/capnp/c++.capnp";
$Cxx.namespace("workerd::rpc");
# We do not use `$Cxx.allowCancellation` because runAlarm() currently depends on blocking
# cancellation.

using import "/capnp/compat/http-over-capnp.capnp".HttpMethod;
using import "/capnp/compat/http-over-capnp.capnp".HttpService;
using import "/workerd/io/outcome.capnp".EventOutcome;
using import "/workerd/io/script-version.capnp".ScriptVersion;

struct Trace @0x8e8d911203762d34 {
  logs @0 :List(Log);
  struct Log {
    timestampNs @0 :Int64;

    logLevel @1 :Level;
    enum Level {
      debug @0 $Cxx.name("debug_");  # avoid collision with macro on Apple platforms
      info @1;
      log @2;
      warn @3;
      error @4;
    }

    message @2 :Text;
  }

  exceptions @1 :List(Exception);
  struct Exception {
    timestampNs @0 :Int64;
    name @1 :Text;
    message @2 :Text;
  }

  outcome @2 :EventOutcome;
  scriptName @4 :Text;
  scriptVersion @19 :ScriptVersion;

  eventTimestampNs @5 :Int64;

  eventInfo :union {
    none @3 :Void;
    fetch @6 :FetchEventInfo;
    scheduled @7 :ScheduledEventInfo;
    alarm @9 :AlarmEventInfo;
    queue @15 :QueueEventInfo;
    custom @13 :CustomEventInfo;
    email @16 :EmailEventInfo;
    trace @18 :TraceEventInfo;
    hibernatableWebSocket @20 :HibernatableWebSocketEventInfo;
  }
  struct FetchEventInfo {
    method @0 :HttpMethod;
    url @1 :Text;
    cfJson @2 :Text;
    # Empty string indicates missing cf blob
    headers @3 :List(Header);
    struct Header {
      name @0 :Text;
      value @1 :Text;
    }
  }

  struct ScheduledEventInfo {
    scheduledTime @0 :Float64;
    cron @1 :Text;
  }

  struct AlarmEventInfo {
    scheduledTimeMs @0 :Int64;
  }

  struct QueueEventInfo {
    queueName @0 :Text;
    batchSize @1 :UInt32;
  }

  struct EmailEventInfo {
    mailFrom @0 :Text;
    rcptTo @1 :Text;
    rawSize @2 :UInt32;
  }

  struct TraceEventInfo {
    struct TraceItem {
      scriptName @0 :Text;
    }

    traces @0 :List(TraceItem);
  }

  struct HibernatableWebSocketEventInfo {
    type :union {
      message @0 :Void;
      close :group {
        code @1 :UInt16;
        wasClean @2 :Bool;
      }
      error @3 :Void;
    }
  }

  struct CustomEventInfo {}

  response @8 :FetchResponseInfo;
  struct FetchResponseInfo {
    statusCode @0 :UInt16;
  }

  cpuTime @10 :UInt64;
  wallTime @11 :UInt64;

  dispatchNamespace @12 :Text;
  scriptTags @14 :List(Text);

  diagnosticChannelEvents @17 :List(DiagnosticChannelEvent);
  struct DiagnosticChannelEvent {
    timestampNs @0 :Int64;
    channel @1 :Text;
    message @2 :Data;
  }
}

struct ScheduledRun @0xd98fc1ae5c8095d0 {
  outcome @0 :EventOutcome;

  retry @1 :Bool;
}

struct AlarmRun @0xfa8ea4e97e23b03d {
  outcome @0 :EventOutcome;

  retry @1 :Bool;
  retryCountsAgainstLimit @2 :Bool = true;
}

struct QueueMessage @0x944adb18c0352295 {
  id @0 :Text;
  timestampNs @1 :Int64;
  data @2 :Data;
  contentType @3 :Text;
}

struct QueueResponse @0x90e98932c0bfc0de {
  outcome @0 :EventOutcome;
  retryAll @1 :Bool;
  ackAll @2 :Bool;
  explicitRetries @3 :List(Text);
  # List of Message IDs that were explicitly marked for retry
  explicitAcks @4 :List(Text);
  # List of Message IDs that were explicitly marked as acknowledged
}

struct HibernatableWebSocketEventMessage {
  payload :union {
    text @0 :Text;
    data @1 :Data;
    close :group {
      code @2 :UInt16;
      reason @3 :Text;
      wasClean @4 :Bool;
    }
    error @5 :Text;
    # TODO(someday): This could be an Exception instead of Text.
  }
  websocketId @6: Text;
  eventTimeoutMs @7: UInt32;
}

struct HibernatableWebSocketResponse {
  outcome @0 :EventOutcome;
}

interface HibernatableWebSocketEventDispatcher {
  hibernatableWebSocketEvent @0 (message: HibernatableWebSocketEventMessage )
      -> (result :HibernatableWebSocketResponse);
  # Run a hibernatable websocket event
}

enum SerializationTag {
  # Tag values for all serializable types supported by the Workers API.

  invalid @0;
  # Not assigned to anything. Reserved to make things less weird if a zero-valued tag gets written
  # by accident.

  jsRpcStub @1;
}

struct JsValue {
  # A serialized JavaScript value being passed over RPC.

  v8Serialized @0 :Data;
  # JS value that has been serialized for network transport.

  externals @1 :List(External);
  # The serialized data may contain "externals" -- references to external resources that cannot
  # simply be serialized. If so, they are placed in this separate list of externals.
  #
  # (We could also call these "capabilities", but that word is pretty overloaded already.)

  struct External {
    union {
      invalid @0 :Void;
      # Invalid default value to reduce confusion if an External wasn't initialized properly.
      # This should never appear in a real JsValue.

      rpcTarget @1 :JsRpcTarget;
      # An object that can be called over RPC.

      # TODO(soon): Streams, Request, Response, etc.
    }
  }
}

interface JsRpcTarget {
  struct CallParams {
    union {
      methodName @0 :Text;
      # Equivalent to `methodPath` where the list has only one element equal to this.

      methodPath @2 :List(Text);
      # Path of properties to follow from the JsRpcTarget itself to find the method being called.
      # E.g. if the application does:
      #
      #     myRpcTarget.foo.bar.baz()
      #
      # Then the path is ["foo", "bar", "baz"].
      #
      # The path can also be empty, which means that the JsRpcTarget itself is being invoked as a
      # function.
    }

    args @1 :JsValue;
    # Arguments to the function. This is a JsValue that always encodes a JavaScript Array
    # containing the arguments to the call.
    #
    # If `args` is null (but is still the active member of the union), this indicates that the
    # argument list is empty.
  }

  call @0 CallParams -> (result :JsValue);
  # Runs a Worker/DO's RPC method.
}

interface EventDispatcher @0xf20697475ec1752d {
  # Interface used to deliver events to a Worker's global event handlers.

  getHttpService @0 () -> (http :HttpService) $Cxx.allowCancellation;
  # Gets the HTTP interface to this worker (to trigger FetchEvents).

  sendTraces @1 (traces :List(Trace)) $Cxx.allowCancellation;
  # Deliver a trace event to a trace worker. This always completes immediately; the trace handler
  # runs as a "waitUntil" task.

  prewarm @2 (url :Text) $Cxx.allowCancellation;

  runScheduled @3 (scheduledTime :Int64, cron :Text) -> (result :ScheduledRun)
      $Cxx.allowCancellation;
  # Runs a scheduled worker. Returns a ScheduledRun, detailing information about the run such as
  # the outcome and whether the run should be retried. This does not complete immediately.


  runAlarm @4 (scheduledTime :Int64) -> (result :AlarmRun);
  # Runs a worker's alarm.
  # scheduledTime is a unix timestamp in milliseconds for when the alarm should be run
  # Returns an AlarmRun, detailing information about the run such as
  # the outcome and whether the run should be retried. This does not complete immediately.
  #
  # TODO(cleanup): runAlarm()'s implementation currently relies on *not* allowing cancellation.
  #   It would be cleaner to handle that inside the implementation so we could mark the entire
  #   interface (and file) with allowCancellation.

  queue @8 (messages :List(QueueMessage), queueName :Text) -> (result :QueueResponse)
      $Cxx.allowCancellation;
  # Delivers a batch of queue messages to a worker's queue event handler. Returns information about
  # the success of the batch, including which messages should be considered acknowledged and which
  # should be retried.

  jsRpcSession @9 () -> (topLevel :JsRpcTarget);
  # Opens a JS rpc "session". The call does not return until the session is complete.
  #
  # `topLevel` is the top-level RPC target, on which exactly one method call can be made. This
  # call must be made using pipelining since `jsRpcSession()` won't return until after the call
  # completes.
  #
  # If, through the one top-level call, new capabilities are exchanged between the client and
  # server, then `jsRpcSession()` won't return until all those capabilities have been dropped.
  #
  # In C++, we use `WorkerInterface::customEvent()` to dispatch this event.

  obsolete5 @5();
  obsolete6 @6();
  obsolete7 @7();
  # Deleted methods, do not reuse these numbers.

  # Other methods might be added to handle other kinds of events, e.g. TCP connections, or maybe
  # even native Cap'n Proto RPC eventually.
}
