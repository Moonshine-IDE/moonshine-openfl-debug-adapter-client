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

/**
	Implementation of `InitializeRequestArguments` interface from Debug Server Protocol

	**DO NOT** add new properties or methods to this class that are specific to
	Moonshine IDE or to a particular language. Create a subclass for new
	properties or create a utility function for methods.

	@see https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Initialize
**/
typedef InitializeRequestArguments = {
	adapterID:String,
	?clientID:String,
	?clientName:String,
	?locale:String,
	?linesStartAt1:Bool,
	?columnsStartAt1:Bool,
	?pathFormat:String,
	?supportsVariableType:Bool,
	?supportsVariablePaging:Bool,
	?supportsRunInTerminalRequest:Bool,
	?supportsMemoryReferences:Bool,
	?supportsProgressReporting:Bool,
	?supportsInvalidatedEvent:Bool,
}
