{Point, Range, TextEditor, TextBuffer, CompositeDisposable, BufferedProcess, NotificationManager} = require 'atom'
{View} = require 'atom-space-pen-views'
GDB = require './backend/gdb/gdb'
fs = require 'fs'
path = require 'path'
AsmViewer = require './asm-viewer'

VariablesView = require './variables-view'
OpenDialogView = require './open-dialog-view'

module.exports =
class DebuggerView extends View
  @content: ->
    @div class: 'atom-debugger', =>
      @header class: 'header', =>
        @span class: 'header-item title', 'Android Debugger'
        @span class: 'header-item sub-title', outlet: 'targetLabel'
      @div class: 'btn-toolbar', =>
        @div class: 'btn-group', =>
          @div class: 'btn', outlet: 'attachButton', 'Attach'
          @div class: 'btn disabled', outlet: 'detachButton', 'Detach'
        @div class: 'btn-group', =>
          @div class: 'btn disabled', outlet: 'continueButton', 'Continue'
          @div class: 'btn disabled', outlet: 'pauseButton', 'Pause'
        @div class: 'btn-group', =>
          @div class: 'btn disabled', outlet: 'stepOverButton', 'Step Over'
          @div class: 'btn disabled', outlet: 'stepIntoButton', 'Step Into'
          @div class: 'btn disabled', outlet: 'stepOutButton', 'Step Out'


  initialize: (target, pid) ->
    gdb = atom.config.get("android-debugger.gdbPath")
    adb = atom.config.get("android-debugger.adbPath")
    libSearchPath = atom.config.get("android-debugger.libSearchPath")
    
    # command = adb

    # stdout = (output) =>
    #   console.debug(output)
    # stderr = (err) =>
    #   console.error(err)

    # # attach to process
    # stdout = (output) =>
    #   @GDB.target 'remote :5039', (clazz, result) ->
    # args = ['shell', '/system/bin/gdbserver', 'tcp:5039', '--attach', pid]
    # @attachToProcess = new BufferedProcess({command, args, stdout, stderr}).process

    @targetLabel.text(target)

    @pid = pid

    @GDB = new GDB(gdb, target)
    @GDB.set 'target-async', 'on', (result) ->
    @GDB.setSourceDirectories atom.project.getPaths(), (done) ->
    @GDB.set 'solib-search-path', libSearchPath, (result) ->
    @GDB.target 'select', 'extended-remote :5039', (clazz, result) ->

    window.gdb = @GDB

    @breaks = {}
    @stopped = {marker: null, fullpath: null, line: null}
    @asms = {}
    @cachedEditors = {}
    @handleEvents()

    contextMenuCreated = (event) =>
      if editor = @getActiveTextEditor()
        component = atom.views.getView(editor).component
        position = component.screenPositionForMouseEvent(event)
        @contextLine = editor.bufferPositionForScreenPosition(position).row

    @menu = atom.contextMenu.add {
      'atom-text-editor': [{
        label: 'Toggle Breakpoint',
        command: 'debugger:toggle-breakpoint',
        created: contextMenuCreated
      }]
    }

    @panel = atom.workspace.addBottomPanel(item: @, visible: true)

    @vars = []
    @varsView = new VariablesView()
    @varsPanel = atom.workspace.addRightPanel(item: @varsView, visible: false)

    @listExecFile()

    @pauseRequired = false

  getActiveTextEditor: ->
    atom.workspace.getActiveTextEditor()

  exists: (fullpath) ->
    return fs.existsSync(fullpath)

  getEditor: (fullpath) ->
    return @cachedEditors[fullpath]

  goExitedStatus: ->
    @pauseButton.addClass('disabled')
    @detachButton.addClass('disabled')

    @continueButton.addClass('disabled')
    @stepIntoButton.addClass('disabled')
    @stepOverButton.addClass('disabled')
    @stepOutButton.addClass('disabled')

    @removeClass('running')
    @addClass('stopped')

  goStoppedStatus: ->
    @pauseButton.addClass('disabled')
    @detachButton.removeClass('disabled')

    @continueButton.removeClass('disabled')

    if not @pauseRequired
      @stepIntoButton.removeClass('disabled')
      @stepOverButton.removeClass('disabled')
      @stepOutButton.removeClass('disabled')

    @removeClass('running')
    @addClass('stopped')

  goRunningStatus: ->
    @stopped.marker?.destroy()
    @stopped = {marker: null, fullpath: null, line: null}

    @pauseButton.removeClass('disabled')
    @detachButton.removeClass('disabled')

    @continueButton.addClass('disabled')
    @stepIntoButton.addClass('disabled')
    @stepOverButton.addClass('disabled')
    @stepOutButton.addClass('disabled')

    @removeClass('stopped')
    @addClass('running')

  insertMainBreak: ->
    @GDB.insertBreak {location: 'main'}, (abreak) =>
      if abreak
        if abreak.fullname
          fullpath = path.resolve(abreak.fullname)
          line = Number(abreak.line)-1
          @insertBreakWithoutEditor(fullpath, line)
        else
          atom.confirm
            detailedMessage: "Can't find debugging symbols\nPlease recompile with `-g` option."
            buttons:
              Exit: => @destroy()

  listExecFile: ->
    @GDB.listExecFile (file) =>
      if file
        fullpath = path.resolve(file.fullname)
        line = Number(file.line) - 1
        if @exists(fullpath)
          atom.workspace.open fullpath, (editor) =>
            @moveToLine(editor, line)
        else
          atom.confirm
            detailedMessage: "Can't find file #{file.file}\nPlease add path to tree-view and try again."
            buttons:
              Exit: => @destroy()

  toggleBreak: (editor, line) ->
    if @hasBreak(editor, line)
      @deleteBreak(editor, line)
    else
      @insertBreak(editor, line)

  hasBreak: (editor, line) ->
    return line of @breaks[editor.getPath()]

  deleteBreak: (editor, line) ->
    fullpath = editor.getPath()
    {abreak, marker} = @breaks[fullpath][line]
    @GDB.deleteBreak abreak.number, (done) =>
      if done
        marker.destroy()
        delete @breaks[fullpath][line]

  insertBreak: (editor, line) ->
    fullpath = editor.getPath()
    @GDB.insertBreak {location: "#{fullpath}:#{line+1}"}, (abreak) =>
      if abreak
        marker = @markBreakLine(editor, line)
        @breaks[fullpath][line] = {abreak, marker}

  insertBreakWithoutEditor: (fullpath, line) ->
    @breaks[fullpath] ?= {}
    @GDB.insertBreak {location: "#{fullpath}:#{line+1}"}, (abreak) =>
      if abreak
        if editor = @getEditor(fullpath)
          marker = @markBreakLine(editor, line)
        else
          marker = null
        @breaks[fullpath][line] = {abreak, marker}

  moveToLine: (editor, line) ->
    editor.scrollToBufferPosition(new Point(line))
    editor.setCursorBufferPosition(new Point(line))
    editor.moveToFirstCharacterOfLine()

  markBreakLine: (editor, line) ->
    range = new Range([line, 0], [line+1, 0])
    marker = editor.markBufferRange(range, {invalidate: 'never'})
    editor.decorateMarker(marker, {type: 'line-number', class: 'debugger-breakpoint-line'})
    return marker

  markStoppedLine: (editor, line) ->
    range = new Range([line, 0], [line+1, 0])
    marker = editor.markBufferRange(range, {invalidate: 'never'})
    editor.decorateMarker(marker, {type: 'line-number', class: 'debugger-stopped-line'})
    editor.decorateMarker(marker, {type: 'highlight', class: 'selection'})

    @moveToLine(editor, line)
    return marker

  refreshBreakMarkers: (editor) ->
    fullpath = editor.getPath()
    for line, {abreak, marker} of @breaks[fullpath]
      marker = @markBreakLine(editor, Number(line))
      @breaks[fullpath][line] = {abreak, marker}

  refreshStoppedMarker: (editor) ->
    fullpath = editor.getPath()
    if fullpath == @stopped.fullpath
      @stopped.marker = @markStoppedLine(editor, @stopped.line)

  hackGutterDblClick: (editor) ->
    component = atom.views.getView(editor).component
    # gutterComponent has been renamed to gutterContainerComponent
    gutter  = component.gutterComponent
    gutter ?= component.gutterContainerComponent

    gutter.domNode.addEventListener 'dblclick', (event) =>
      unless @GDB.isDestroyed()
        position = component.screenPositionForMouseEvent(event)
        line = editor.bufferPositionForScreenPosition(position).row
        @toggleBreak(editor, line)
        selection = editor.selectionsForScreenRows(line, line + 1)[0]
        selection?.clear()

  handleEvents: ->
    @subscriptions = new CompositeDisposable

    @subscriptions.add atom.commands.add 'atom-workspace', 'debugger:toggle-breakpoint', =>
      @toggleBreak(@getActiveTextEditor(), @contextLine)

    @subscriptions.add atom.workspace.observeTextEditors (editor) =>
      fullpath = editor.getPath()
      @cachedEditors[fullpath] = editor
      @breaks[fullpath] ?= {}
      @refreshBreakMarkers(editor)
      @refreshStoppedMarker(editor)
      @hackGutterDblClick(editor)

    @subscriptions.add atom.project.onDidChangePaths (paths) =>
      @GDB.setSourceDirectories paths, (done) ->

    # @runButton.on 'click', =>
    #   @GDB.run (result) ->    

    @attachButton.on 'click', =>
      @openDialogView = new OpenDialogView (pid) =>
        atom.config.set('android-debugger.processId', pid)
        @pid = pid

        do (@GDB, @pid, @destroy) ->
          @GDB.target 'attach', @pid, (ok) ->
            if ok
              atom.notifications.addSuccess "Attached to process #{@pid}", { dismissable: true }
            else
              atom.notifications.addError "Attaching to process #{@pid} failed", { dismissable: true }

    @continueButton.on 'click', =>
      @GDB.continue (result) ->
        console.log(result)

    @detachButton.on 'click', =>
      @pauseRequired = true
      @GDB.interrupt (result) =>
        @detachRequired = true

    @pauseButton.on 'click', =>
      @pauseRequired = true
      @GDB.interrupt (result) ->
        console.log(result)

    @stepOverButton.on 'click', =>
      @GDB.next (result) ->
        console.log(result)

    @stepIntoButton.on 'click', =>
      @GDB.step (result) ->
        console.log(result)

    @stepOutButton.on 'click', =>
      @GDB.finish (result) ->
        console.log(result)

    @GDB.onExecAsyncRunning (result) =>
      @goRunningStatus()
      console.log(result)

      
      #remove gdb vars
      for item in @vars
        @GDB.var "delete", "#{item.name}"

      #clear @vars
      @vars.length = 0

      # @varsView.setItems(@vars)
      # @varsView.setLoading('Waiting...')

    @GDB.onExecAsyncStopped (result) =>
      @goStoppedStatus()
      console.log(result)

      unless frame = result.frame
        @goExitedStatus()
      else
        if frame.fullname
          fullpath = path.resolve(frame.fullname)
          line = Number(frame.line)-1

          if @exists(fullpath)
            atom.workspace.open(fullpath, {debugging: true, fullpath: fullpath, startline: line}).done (editor) =>
              @stopped = {marker: @markStoppedLine(editor, line), fullpath, line}

            @varsPanel.show()
            @GDB.stack 'list-arguments', '--all-values', (ok, data) =>
              if ok
                for item in data['stack-args'].frame[0].args
                  do (item, @GDB, @vars, @varsView) =>
                    #create gdb var
                    @GDB.var "create", "#{item.name} * \"#{item.name}\"", (ok, data) =>
                      if ok
                        @vars.push
                          name: item.name
                          type: data.type
                          value: item.value
                        @varsView.setItems(@vars)
                
          else
            @GDB.next (result) ->
        else
          if not @pauseRequired
            @GDB.next (result) ->
          @pauseRequired = false

          if @detachRequired
            @detachRequired = false
            @GDB.target 'detach', @pid, (result) =>
              @goExitedStatus()
              console.log(result)
          

  # Tear down any state and detach
  destroy: ->
    @GDB.destroy()
    @subscriptions.dispose()
    @stopped.marker?.destroy()
    @menu.dispose()

    for fullpath, breaks of @breaks
      for line, {abreak, marker} of breaks
        marker.destroy()

    for editor in atom.workspace.getTextEditors()
      component = atom.views.getView(editor).component
      gutter  = component.gutterComponent
      gutter ?= component.gutterContainerComponent
      gutter.domNode.removeEventListener 'dblclick'

    @panel.destroy()
    @varsPanel.destroy()
    @detach()
