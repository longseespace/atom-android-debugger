DebuggerView = require './debugger-view'
{CompositeDisposable} = require 'atom'
fs = require 'fs'

module.exports = Debugger =
  subscriptions: null

  config:
    gdbPath:
      type: 'string'
      default: "Path to the gdb"
    adbPath:
      type: 'string'
      default: "Path to the adb"
    libSearchPath:
      type: 'string'
      default: "Shared library search path"
    targetBinary:
      type: 'string'
      default: 'Target Binary'
    processId:
      type: 'string'
      default: ''

  activate: (state) ->
    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register command that toggles this view
    @subscriptions.add atom.commands.add 'atom-workspace', 'debugger:toggle': => @toggle()
    @subscriptions.add atom.commands.add 'atom-workspace', 'core:close': =>
      @debuggerView?.destroy()
      @debuggerView = null
    @subscriptions.add atom.commands.add 'atom-workspace', 'core:cancel': =>
      @debuggerView?.destroy()
      @debuggerView = null

  deactivate: ->
    @subscriptions.dispose()
    # @openDialogView.destroy()
    @debuggerView?.destroy()

  serialize: ->

  toggle: ->
    if @debuggerView and @debuggerView.hasParent()
      @debuggerView.destroy()
      @debuggerView = null
    else
      # @openDialogView = new OpenDialogView (pid) =>
      target = atom.config.get("android-debugger.targetBinary")
      # atom.config.set('android-debugger.processId', pid)
      if fs.existsSync(target)
        @debuggerView = new DebuggerView(target)
      else
        atom.confirm
          detailedMessage: "Can't find file #{target}."
          buttons:
            Exit: =>
