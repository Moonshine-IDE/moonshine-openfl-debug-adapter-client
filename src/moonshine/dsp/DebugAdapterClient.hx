/*
	Licensed under the Apache License, Version 2.0 (the "License");
	you may not use this file except in compliance with the License.
	You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

	Unless required by applicable law or agreed to in writing, software
	distributed under the License is distributed on an "AS IS" BASIS,
	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
	See the License for the specific language governing permissions and
	limitations under the License

	No warranty of merchantability or fitness of any kind.
	Use this software at your own risk.
 */

package moonshine.dsp;

import haxe.Json;
import openfl.errors.IllegalOperationError;
import openfl.events.Event;
import openfl.events.EventDispatcher;
import openfl.events.IEventDispatcher;
import openfl.utils.ByteArray;
import openfl.utils.IDataInput;
import openfl.utils.IDataOutput;

/**
	An implementation of the debug adapter protocol for Moonshine IDE.
	@see https://microsoft.github.io/debug-adapter-protocol/specification Language Server Protocol Specification
**/
class DebugAdapterClient extends EventDispatcher {
	private static final HELPER_BYTES:ByteArray = new ByteArray();
	private static final PROTOCOL_HEADER_FIELD_CONTENT_LENGTH:String = "Content-Length: ";
	private static final PROTOCOL_END_OF_HEADER:String = "\r\n\r\n";
	private static final PROTOCOL_HEADER_DELIMITER:String = "\r\n";
	private static final MESSAGE_TYPE_REQUEST:String = "request";
	private static final MESSAGE_TYPE_RESPONSE:String = "response";
	private static final MESSAGE_TYPE_EVENT:String = "event";
	private static final COMMAND_INITIALIZE:String = "initialize";
	private static final COMMAND_LAUNCH:String = "launch";
	private static final COMMAND_ATTACH:String = "attach";
	private static final COMMAND_THREADS:String = "threads";
	private static final COMMAND_SET_BREAKPOINTS:String = "setBreakpoints";
	private static final COMMAND_PAUSE:String = "pause";
	private static final COMMAND_CONTINUE:String = "continue";
	private static final COMMAND_NEXT:String = "next";
	private static final COMMAND_STEP_IN:String = "stepIn";
	private static final COMMAND_STEP_OUT:String = "stepOut";
	private static final COMMAND_DISCONNECT:String = "disconnect";
	private static final COMMAND_SCOPES:String = "scopes";
	private static final COMMAND_STACK_TRACE:String = "stackTrace";
	private static final COMMAND_VARIABLES:String = "variables";
	private static final COMMAND_CONFIGURATION_DONE:String = "configurationDone";
	private static final PREINITIALIZED_COMMANDS = [COMMAND_LAUNCH, COMMAND_ATTACH, COMMAND_DISCONNECT];
	private static final EVENT_INITIALIZED:String = "initialized";
	private static final EVENT_BREAKPOINT:String = "breakpoint";
	private static final EVENT_OUTPUT:String = "output";
	private static final EVENT_STOPPED:String = "stopped";
	private static final EVENT_TERMINATED:String = "terminated";
	private static final EVENT_LOADED_SOURCE:String = "loadedSource";
	private static final EVENT_CONTINUED:String = "continued";
	private static final EVENT_THREAD:String = "thread";
	private static final REQUEST_LAUNCH:String = "launch";
	private static final REQUEST_ATTACH:String = "attach";
	private static final OUTPUT_CATEGORY_CONSOLE:String = "console";
	private static final OUTPUT_CATEGORY_STDOUT:String = "stdout";
	private static final OUTPUT_CATEGORY_STDERR:String = "stderr";
	private static final OUTPUT_CATEGORY_TELEMETRY:String = "telemetry";
	private static final FIELD_TYPE:String = "type";

	public function new(input:IDataInput, inputDispatcher:IEventDispatcher, inputEventType:String, output:IDataOutput, outputFlushCallback:() -> Void = null) {
		super();
		_input = input;
		_inputDispatcher = inputDispatcher;
		_inputEventType = inputEventType;
		_output = output;
		_outputFlushCallback = outputFlushCallback;
	}

	public var debugMode:Bool = false;

	private var _input:IDataInput;
	private var _inputDispatcher:IEventDispatcher;
	private var _inputEventType:String;
	private var _output:IDataOutput;
	private var _outputFlushCallback:() -> Void;

	private var _calledInitialize:Bool = false;
	private var _contentLength:Int = -1;
	private var _seq:Int = 0;
	private var _messageBuffer:String = "";
	private var _messageBytes:ByteArray = new ByteArray();

	private var _receivedInitializeResponse = false;
	private var _receivedInitializedEvent = false;

	@:flash.property
	public var initialized(get, never):Bool;

	private function get_initialized():Bool {
		return _receivedInitializeResponse && _receivedInitializedEvent;
	}

	private var _waitingForLaunchOrAttach = false;
	private var _handledPostInit = false;

	private var _protocolEventListeners:Map<String, Array<(event:DebugProtocolEvent) -> Void>> = [];

	private var _idToRequest:Map<Int, DebugProtocolRequest> = [];
	private var _initializeLookup:Map<Int, ArgsAndCallbacks<InitializeRequestArguments, (Capabilities) -> Void, (ErrorResponseBody) -> Void>> = [];
	private var _configurationDoneLookup:Map<Int, ArgsAndCallbacks<ConfigurationDoneArguments, () -> Void, (ErrorResponseBody) -> Void>> = [];
	private var _attachLookup:Map<Int, ArgsAndCallbacks<AttachRequestArguments, () -> Void, (ErrorResponseBody) -> Void>> = [];
	private var _launchLookup:Map<Int, ArgsAndCallbacks<LaunchRequestArguments, () -> Void, (ErrorResponseBody) -> Void>> = [];
	private var _disconnectLookup:Map<Int, ArgsAndCallbacks<DisconnectArguments, () -> Void, (ErrorResponseBody) -> Void>> = [];
	private var _threadsLookup:Map<Int, ArgsAndCallbacks<Any, (ThreadsResponseBody) -> Void, (ErrorResponseBody) -> Void>> = [];
	private var _setBreakpointsLookup:Map<Int,
		ArgsAndCallbacks<SetBreakpointsArguments, (SetBreakpointsResponseBody) -> Void, (ErrorResponseBody) -> Void>> = [];
	private var _stackTraceLookup:Map<Int, ArgsAndCallbacks<StackTraceArguments, (StackTraceResponseBody) -> Void, (ErrorResponseBody) -> Void>> = [];
	private var _scopesLookup:Map<Int, ArgsAndCallbacks<ScopesArguments, (ScopesResponseBody) -> Void, (ErrorResponseBody) -> Void>> = [];
	private var _variablesLookup:Map<Int, ArgsAndCallbacks<VariablesArguments, (VariablesResponseBody) -> Void, (ErrorResponseBody) -> Void>> = [];
	private var _pauseLookup:Map<Int, ArgsAndCallbacks<PauseArguments, () -> Void, (ErrorResponseBody) -> Void>> = [];
	private var _continueLookup:Map<Int, ArgsAndCallbacks<ContinueArguments, (ContinueResponseBody) -> Void, (ErrorResponseBody) -> Void>> = [];
	private var _stepInLookup:Map<Int, ArgsAndCallbacks<StepInArguments, () -> Void, (ErrorResponseBody) -> Void>> = [];
	private var _stepOutLookup:Map<Int, ArgsAndCallbacks<StepOutArguments, () -> Void, (ErrorResponseBody) -> Void>> = [];
	private var _nextLookup:Map<Int, ArgsAndCallbacks<NextArguments, () -> Void, (ErrorResponseBody) -> Void>> = [];

	public function addProtocolEventListener(method:String, listener:(DebugProtocolEvent) -> Void):Void {
		if (!_protocolEventListeners.exists(method)) {
			_protocolEventListeners.set(method, []);
		}
		var listeners = _protocolEventListeners.get(method);
		var index = listeners.indexOf(listener);
		if (index != -1) {
			// already added
			return;
		}
		listeners.push(listener);
	}

	public function removeProtocolEventListener(method:String, listener:(DebugProtocolEvent) -> Void):Void {
		if (!_protocolEventListeners.exists(method)) {
			// nothing to remove
			return;
		}
		var listeners = _protocolEventListeners.get(method);
		var index = listeners.indexOf(listener);
		if (index == -1) {
			// nothing to remove
			return;
		}
		listeners.splice(index, 1);
	}

	public function initialize(args:InitializeRequestArguments, onSuccess:(Capabilities) -> Void, ?onError:(ErrorResponseBody) -> Void):Void {
		if (_calledInitialize) {
			throw new IllegalOperationError('Cannot call initialize() more than once');
		}
		_calledInitialize = true;
		_inputDispatcher.addEventListener(_inputEventType, debugAdapterClient_input_onData);
		var seq = sendRequest(COMMAND_INITIALIZE, args);
		_initializeLookup.set(seq, new ArgsAndCallbacks(args, onSuccess, onError));
	}

	public function configurationDone(args:ConfigurationDoneArguments, onSuccess:() -> Void, ?onError:(ErrorResponseBody) -> Void):Void {
		var seq = sendRequest(COMMAND_CONFIGURATION_DONE, args);
		_configurationDoneLookup.set(seq, new ArgsAndCallbacks(args, onSuccess, onError));
	}

	public function attach(args:AttachRequestArguments, onSuccess:() -> Void, ?onError:(ErrorResponseBody) -> Void):Void {
		_waitingForLaunchOrAttach = true;
		var seq = sendRequest(COMMAND_ATTACH, args);
		_attachLookup.set(seq, new ArgsAndCallbacks(args, onSuccess, onError));
	}

	public function launch(args:LaunchRequestArguments, onSuccess:() -> Void, ?onError:(ErrorResponseBody) -> Void):Void {
		_waitingForLaunchOrAttach = true;
		var seq = sendRequest(COMMAND_LAUNCH, args);
		_launchLookup.set(seq, new ArgsAndCallbacks(args, onSuccess, onError));
	}

	public function disconnect(args:DisconnectArguments, onSuccess:() -> Void, ?onError:(ErrorResponseBody) -> Void):Void {
		if (_receivedInitializeResponse && !_waitingForLaunchOrAttach) {
			var seq = sendRequest(COMMAND_DISCONNECT, args);
			_disconnectLookup.set(seq, new ArgsAndCallbacks(args, onSuccess, onError));
		} else {
			// if we haven't yet received a response to the initialize
			// request or if we're waiting for a response to attach/launch,
			// then we need to force the debug adapter to stop because it
			// won't be able to handle the disconnect request
			handleDisconnectOrTerminated();
			onSuccess();
		}
	}

	public function threads(args:Any, onSuccess:(ThreadsResponseBody) -> Void, ?onError:(ErrorResponseBody) -> Void):Void {
		var seq = sendRequest(COMMAND_THREADS, args);
		_threadsLookup.set(seq, new ArgsAndCallbacks(args, onSuccess, onError));
	}

	public function setBreakpoints(args:SetBreakpointsArguments, onSuccess:(SetBreakpointsResponseBody) -> Void, ?onError:(ErrorResponseBody) -> Void):Void {
		var seq = sendRequest(COMMAND_SET_BREAKPOINTS, args);
		_setBreakpointsLookup.set(seq, new ArgsAndCallbacks(args, onSuccess, onError));
	}

	public function stackTrace(args:StackTraceArguments, onSuccess:(StackTraceResponseBody) -> Void, ?onError:(ErrorResponseBody) -> Void):Void {
		var seq = sendRequest(COMMAND_STACK_TRACE, args);
		_stackTraceLookup.set(seq, new ArgsAndCallbacks(args, onSuccess, onError));
	}

	public function scopes(args:ScopesArguments, onSuccess:(ScopesResponseBody) -> Void, ?onError:(ErrorResponseBody) -> Void):Void {
		var seq = sendRequest(COMMAND_SCOPES, args);
		_scopesLookup.set(seq, new ArgsAndCallbacks(args, onSuccess, onError));
	}

	public function variables(args:VariablesArguments, onSuccess:(VariablesResponseBody) -> Void, ?onError:(ErrorResponseBody) -> Void):Void {
		var seq = sendRequest(COMMAND_VARIABLES, args);
		_variablesLookup.set(seq, new ArgsAndCallbacks(args, onSuccess, onError));
	}

	public function pauseThread(args:ContinueArguments, onSuccess:() -> Void, ?onError:(ErrorResponseBody) -> Void):Void {
		var seq = sendRequest(COMMAND_PAUSE, args);
		_pauseLookup.set(seq, new ArgsAndCallbacks(args, onSuccess, onError));
	}

	public function continueThread(args:ContinueArguments, onSuccess:(ContinueResponseBody) -> Void, ?onError:(ErrorResponseBody) -> Void):Void {
		var seq = sendRequest(COMMAND_CONTINUE, args);
		_continueLookup.set(seq, new ArgsAndCallbacks(args, onSuccess, onError));
	}

	public function stepIn(args:StepInArguments, onSuccess:() -> Void, ?onError:(ErrorResponseBody) -> Void):Void {
		var seq = sendRequest(COMMAND_STEP_IN, args);
		_stepInLookup.set(seq, new ArgsAndCallbacks(args, onSuccess, onError));
	}

	public function stepOut(args:StepOutArguments, onSuccess:() -> Void, ?onError:(ErrorResponseBody) -> Void):Void {
		var seq = sendRequest(COMMAND_STEP_OUT, args);
		_stepOutLookup.set(seq, new ArgsAndCallbacks(args, onSuccess, onError));
	}

	public function next(args:NextArguments, onSuccess:() -> Void, ?onError:(ErrorResponseBody) -> Void):Void {
		var seq = sendRequest(COMMAND_NEXT, args);
		_nextLookup.set(seq, new ArgsAndCallbacks(args, onSuccess, onError));
	}

	private function sendRequest(command:String, args:Any = null):Int {
		if (command != COMMAND_INITIALIZE && !_receivedInitializeResponse) {
			throw new IllegalOperationError('Send request failed. Must wait for initialize response before sending request of type "${command}" to the debug adapter.');
		}
		if (PREINITIALIZED_COMMANDS.indexOf(command) == -1 && _receivedInitializeResponse && !_receivedInitializedEvent) {
			throw new IllegalOperationError('Send request failed. Must wait for initialized event before sending request of type "${command}" to the debug adapter.');
		}
		_seq++;
		var message:DebugProtocolRequest = {
			type: MESSAGE_TYPE_REQUEST,
			seq: _seq,
			command: command
		};
		if (args != null) {
			message.arguments = args;
		}
		_idToRequest.set(_seq, message);
		sendProtocolMessage(message);
		return _seq;
	}

	private function sendProtocolMessage(message:DebugProtocolMessage):Void {
		var contentJSON:String = Json.stringify(message);
		if (debugMode) {
			trace("<<< ", contentJSON);
		}
		HELPER_BYTES.clear();
		HELPER_BYTES.writeUTFBytes(contentJSON);
		var contentLength = HELPER_BYTES.length;
		HELPER_BYTES.clear();
		_output.writeUTFBytes(PROTOCOL_HEADER_FIELD_CONTENT_LENGTH);
		_output.writeUTFBytes(Std.string(contentLength));
		_output.writeUTFBytes(PROTOCOL_END_OF_HEADER);
		_output.writeUTFBytes(contentJSON);
		if (_outputFlushCallback != null) {
			_outputFlushCallback();
		}
	}

	private function parseMessageBuffer():Void {
		var object:Any = null;
		try {
			var needsHeaderPart = _contentLength == -1;
			if (needsHeaderPart && _messageBuffer.indexOf(PROTOCOL_END_OF_HEADER) == -1) {
				// not enough data for the header yet
				return;
			}
			while (needsHeaderPart) {
				var index = _messageBuffer.indexOf(PROTOCOL_HEADER_DELIMITER);
				var headerField = _messageBuffer.substr(0, index);
				_messageBuffer = _messageBuffer.substr(index + PROTOCOL_HEADER_DELIMITER.length);
				if (index == 0) {
					// this is the end of the header
					needsHeaderPart = false;
				} else if (headerField.indexOf(PROTOCOL_HEADER_FIELD_CONTENT_LENGTH) == 0) {
					var contentLengthAsString = headerField.substr(PROTOCOL_HEADER_FIELD_CONTENT_LENGTH.length);
					_contentLength = Std.parseInt(contentLengthAsString);
				}
			}
			if (_contentLength == -1) {
				trace("Error: Debug adapter client failed to parse Content-Length header");
				return;
			}
			// keep adding to the byte array until we have the full content
			_messageBytes.writeUTFBytes(_messageBuffer);
			_messageBuffer = "";
			if (Std.int(_messageBytes.length) < _contentLength) {
				// we don't have the full content part of the message yet,
				// so we'll try again the next time we have new data
				return;
			}
			_messageBytes.position = 0;
			var message = _messageBytes.readUTFBytes(_contentLength);
			// add any remaining bytes back into the buffer because they are
			// the beginning of the next message
			_messageBuffer = _messageBytes.readUTFBytes(_messageBytes.length - _contentLength);
			_messageBytes.clear();
			_contentLength = -1;
			object = Json.parse(message);
		} catch (error:Dynamic) {
			trace("Error: Debug adapter client failed to parse JSON.");
			return;
		}
		parseProtocolMessage(object);

		// check if there's another message in the buffer
		parseMessageBuffer();
	}

	private function parseProtocolMessage(message:Any):Void {
		if (Reflect.hasField(message, FIELD_TYPE)) {
			var messageType = Reflect.field(message, FIELD_TYPE);
			switch (messageType) {
				case MESSAGE_TYPE_RESPONSE:
					parseResponseMessage((message : DebugProtocolResponse));
				case MESSAGE_TYPE_EVENT:
					parseEventMessage((message : DebugProtocolEvent));
				default:
					trace('Cannot parse debug message. Unknown type: "${messageType}", Full message: ${Json.stringify(message)}');
			}
		} else {
			trace('Cannot parse debug message. Missing type. Full message: ${Json.stringify(message)}');
		}
	}

	private function parseResponseMessage(response:DebugProtocolResponse):Void {
		if (debugMode) {
			trace(">>> (RESPONSE) ", Json.stringify(response));
		}
		var requestID = Std.int(response.request_seq);
		var originalRequest = _idToRequest.get(requestID);
		if (debugMode && response.success != true) {
			trace('Failed Request: ${Json.stringify(originalRequest)}');
		}
		_idToRequest.remove(requestID);
		switch (response.command) {
			case COMMAND_INITIALIZE:
				if (_initializeLookup.exists(requestID)) {
					_receivedInitializeResponse = true;
					var paramsAndCallbacks = _initializeLookup.get(requestID);
					_initializeLookup.remove(requestID);
					if (response.success) {
						paramsAndCallbacks.onSuccess((response.body : Capabilities));
					} else {
						if (paramsAndCallbacks.onError != null) {
							paramsAndCallbacks.onError((response.body : ErrorResponseBody));
						}
						handleProtocolEvent({
							type: MESSAGE_TYPE_EVENT,
							seq: 0,
							event: EVENT_TERMINATED
						});
					}
				}
			case COMMAND_CONFIGURATION_DONE:
				if (_configurationDoneLookup.exists(requestID)) {
					var paramsAndCallbacks = _configurationDoneLookup.get(requestID);
					_configurationDoneLookup.remove(requestID);
					if (response.success) {
						paramsAndCallbacks.onSuccess();
					} else if (paramsAndCallbacks.onError != null) {
						paramsAndCallbacks.onError((response.body : ErrorResponseBody));
					}
				}
			case COMMAND_ATTACH:
				if (_attachLookup.exists(requestID)) {
					var paramsAndCallbacks = _attachLookup.get(requestID);
					_attachLookup.remove(requestID);
					if (response.success) {
						paramsAndCallbacks.onSuccess();
					} else if (paramsAndCallbacks.onError != null) {
						paramsAndCallbacks.onError((response.body : ErrorResponseBody));
					}
				}
			case COMMAND_LAUNCH:
				if (_launchLookup.exists(requestID)) {
					var paramsAndCallbacks = _launchLookup.get(requestID);
					_launchLookup.remove(requestID);
					if (response.success) {
						paramsAndCallbacks.onSuccess();
					} else if (paramsAndCallbacks.onError != null) {
						paramsAndCallbacks.onError((response.body : ErrorResponseBody));
					}
				}
			case COMMAND_DISCONNECT:
				if (_disconnectLookup.exists(requestID)) {
					var paramsAndCallbacks = _disconnectLookup.get(requestID);
					_disconnectLookup.remove(requestID);
					handleDisconnectOrTerminated();
					if (response.success) {
						paramsAndCallbacks.onSuccess();
					} else if (paramsAndCallbacks.onError != null) {
						paramsAndCallbacks.onError((response.body : ErrorResponseBody));
					}
				}
			case COMMAND_THREADS:
				if (_threadsLookup.exists(requestID)) {
					var paramsAndCallbacks = _threadsLookup.get(requestID);
					_threadsLookup.remove(requestID);
					if (response.success) {
						paramsAndCallbacks.onSuccess((response.body : ThreadsResponseBody));
					} else if (paramsAndCallbacks.onError != null) {
						paramsAndCallbacks.onError((response.body : ErrorResponseBody));
					}
				}
			case COMMAND_SET_BREAKPOINTS:
				if (_setBreakpointsLookup.exists(requestID)) {
					var paramsAndCallbacks = _setBreakpointsLookup.get(requestID);
					_setBreakpointsLookup.remove(requestID);
					if (response.success) {
						paramsAndCallbacks.onSuccess((response.body : SetBreakpointsResponseBody));
					} else if (paramsAndCallbacks.onError != null) {
						paramsAndCallbacks.onError((response.body : ErrorResponseBody));
					}
				}
			case COMMAND_STACK_TRACE:
				if (_stackTraceLookup.exists(requestID)) {
					var paramsAndCallbacks = _stackTraceLookup.get(requestID);
					_stackTraceLookup.remove(requestID);
					if (response.success) {
						paramsAndCallbacks.onSuccess((response.body : StackTraceResponseBody));
					} else if (paramsAndCallbacks.onError != null) {
						paramsAndCallbacks.onError((response.body : ErrorResponseBody));
					}
				}
			case COMMAND_SCOPES:
				if (_scopesLookup.exists(requestID)) {
					var paramsAndCallbacks = _scopesLookup.get(requestID);
					_scopesLookup.remove(requestID);
					if (response.success) {
						paramsAndCallbacks.onSuccess((response.body : ScopesResponseBody));
					} else if (paramsAndCallbacks.onError != null) {
						paramsAndCallbacks.onError((response.body : ErrorResponseBody));
					}
				}
			case COMMAND_VARIABLES:
				if (_variablesLookup.exists(requestID)) {
					var paramsAndCallbacks = _variablesLookup.get(requestID);
					_variablesLookup.remove(requestID);
					if (response.success) {
						paramsAndCallbacks.onSuccess((response.body : VariablesResponseBody));
					} else if (paramsAndCallbacks.onError != null) {
						paramsAndCallbacks.onError((response.body : ErrorResponseBody));
					}
				}
			case COMMAND_PAUSE:
				if (_pauseLookup.exists(requestID)) {
					var paramsAndCallbacks = _pauseLookup.get(requestID);
					_pauseLookup.remove(requestID);
					if (response.success) {
						paramsAndCallbacks.onSuccess();
					} else if (paramsAndCallbacks.onError != null) {
						paramsAndCallbacks.onError((response.body : ErrorResponseBody));
					}
				}
			case COMMAND_CONTINUE:
				if (_continueLookup.exists(requestID)) {
					var paramsAndCallbacks = _continueLookup.get(requestID);
					_continueLookup.remove(requestID);
					if (response.success) {
						paramsAndCallbacks.onSuccess((response.body : ContinueResponseBody));
					} else if (paramsAndCallbacks.onError != null) {
						paramsAndCallbacks.onError((response.body : ErrorResponseBody));
					}
				}
			case COMMAND_STEP_IN:
				if (_stepInLookup.exists(requestID)) {
					var paramsAndCallbacks = _stepInLookup.get(requestID);
					_stepInLookup.remove(requestID);
					if (response.success) {
						paramsAndCallbacks.onSuccess();
					} else if (paramsAndCallbacks.onError != null) {
						paramsAndCallbacks.onError((response.body : ErrorResponseBody));
					}
				}
			case COMMAND_STEP_OUT:
				if (_stepOutLookup.exists(requestID)) {
					var paramsAndCallbacks = _stepOutLookup.get(requestID);
					_stepOutLookup.remove(requestID);
					if (response.success) {
						paramsAndCallbacks.onSuccess();
					} else if (paramsAndCallbacks.onError != null) {
						paramsAndCallbacks.onError((response.body : ErrorResponseBody));
					}
				}
			case COMMAND_NEXT:
				if (_nextLookup.exists(requestID)) {
					var paramsAndCallbacks = _nextLookup.get(requestID);
					_nextLookup.remove(requestID);
					if (response.success) {
						paramsAndCallbacks.onSuccess();
					} else if (paramsAndCallbacks.onError != null) {
						paramsAndCallbacks.onError((response.body : ErrorResponseBody));
					}
				}
			default:
				if (debugMode) {
					trace('Cannot parse debug response. Unknown command: "${response.command}", Full message: ${Json.stringify(response)}');
				}
		}
	}

	private function parseEventMessage(object:DebugProtocolEvent):Void {
		if (debugMode) {
			trace(">>> (EVENT) ", Json.stringify(object));
		}
		var found = true;
		var canHandleProtocolEvent = false;
		switch (object.event) {
			case EVENT_INITIALIZED:
				_receivedInitializedEvent = true;
				canHandleProtocolEvent = true;
			case EVENT_TERMINATED:
				handleDisconnectOrTerminated();
				canHandleProtocolEvent = true;
			default:
				found = false;
		}
		if (!found || canHandleProtocolEvent) {
			found = handleProtocolEvent(object) || found;
		}
		if (!found) {
			trace('Warning: Debug adapter sent event with method named "${object.event}", but no protocol event handlers are registered for this method.');
		}
	}

	private function handleProtocolEvent(object:DebugProtocolEvent):Bool {
		var event = object.event;
		if (!_protocolEventListeners.exists(event)) {
			return false;
		}
		var listeners = _protocolEventListeners.get(event);
		var listenerCount = listeners.length;
		if (listenerCount == 0) {
			return false;
		}
		for (listener in listeners) {
			listener(object);
		}
		return true;
	}

	private function handleDisconnectOrTerminated():Void {
		// this function may be called when the debug adapter is in a bad
		// state. it may not have even started, or it may not be connected.
		// be careful what variables you access because some may be null.
		_receivedInitializeResponse = false;
		_receivedInitializedEvent = false;
		_waitingForLaunchOrAttach = false;
		_handledPostInit = false;

		_inputDispatcher.removeEventListener(_inputEventType, debugAdapterClient_input_onData);
	}

	private function debugAdapterClient_input_onData(event:Event):Void {
		_messageBuffer += _input.readUTFBytes(_input.bytesAvailable);
		parseMessageBuffer();
	}
}

private class ArgsAndCallbacks<ArgsType, SuccessCallbackType, ErrorCallbackType> {
	public var args:ArgsType;
	public var onSuccess:SuccessCallbackType;
	public var onError:ErrorCallbackType;

	public function new(args:ArgsType, onSuccess:SuccessCallbackType, onError:ErrorCallbackType) {
		this.args = args;
		this.onSuccess = onSuccess;
		this.onError = onError;
	}
}
