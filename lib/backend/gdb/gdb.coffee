{BufferedProcess, Emitter} = require 'atom'
{RESULT, parser} = require './gdb-mi-parser'

module.exports =
  class GDB

    STATUS =
      NOTHING: 0
      RUNNING: 1
      STOPPED: 2
      DESTROYED: 3

    constructor: (gdb, target) ->
      @token = 0
      @handler = {}
      @emitter = new Emitter

      stdout = (lines) =>
        console.log(lines)
        for line in lines.split('\n')
          switch line[0]
            when '+' then null  # status-async-output
            when '=' then null  # notify-async-output
            when '~' then null  # console-stream-output
            when '@' then null  # target-stream-output
            when '&' then null  # log-stream-output
            when '*'            # exec-async-output
              {clazz, result} = parser.parse(line.substr(1))
              @emitter.emit 'exec-async-output', {clazz, result}
              @emitter.emit "exec-async-running", result if clazz == RESULT.RUNNING
              @emitter.emit "exec-async-stopped", result if clazz == RESULT.STOPPED

            else                # result-record
              if line[0] <= '9' and line[0] >= '0'
                {token, clazz, result} = parser.parse(line)
                @handler[token](clazz, result)
                delete @handler[token]

      stderr = (lines) =>
        console.info(lines)

      command = gdb
      args = ['--interpreter=mi2', target] #
      console.log("gdb", gdb)
      console.log("target", target)
      @process = new BufferedProcess({command, args, stdout, stderr}).process
      @stdin = @process.stdin
      @status = STATUS.NOTHING

    destroy: ->
      @status = STATUS.DESTROYED
      @process.kill()
      @emitter.dispose()

    isRunning: ->
      @status is STATUS.RUNNING

    isStopped: ->
      @status is STATUS.STOPPED

    isDestroyed: ->
      @status is STATUS.DESTROYED

    onExecAsyncOutput: (callback) ->
      @emitter.on 'exec-async-output', callback

    onExecAsyncStopped: (callback) ->
      @status = STATUS.STOPPED
      @emitter.on 'exec-async-stopped', callback

    onExecAsyncRunning: (callback) ->
      @status = STATUS.RUNNING
      @emitter.on 'exec-async-running', callback

    listFiles: (handler) ->
      @postCommand 'file-list-exec-source-files', (clazz, result) =>
        files = []
        if clazz == RESULT.DONE
          for file in result.files
            files.push(file.fullname)
        handler(files)

    listExecFile: (handler) ->
      @postCommand 'file-list-exec-source-file', (clazz, result) =>
        file = null
        if clazz == RESULT.DONE
          file = result
        handler(file)

    setSourceDirectories: (directories, handler) ->
      args = []
      args.push("\"#{directory}\"") for directory in directories

      command = 'environment-directory ' + args.join(' ')
      @postCommand command, (clazz, result) =>
        handler(clazz == RESULT.DONE)

    listBreaks: (handler) ->
      @postCommand 'break-list', (clazz, result) =>
        breaks = []
        if clazz == RESULT.DONE and result.BreakpointTable.body.bkpt
          breaks = result.BreakpointTable.body.bkpt
        handler(breaks)

    deleteBreak: (number, handler) ->
      command = "break-delete #{number}"
      @postCommand command, (clazz, result) =>
        handler(clazz == RESULT.DONE)

    disassembleData: ({address, file, mode}, handler) ->
      args = []
      if address
        args.push("-s #{address.start}")
        args.push("-e #{address.end}")
      else if file
        args.push("-f #{file.name}")
        args.push("-l #{file.linenum}")
        args.push("-n #{file.lines}") if file.lines
      args.push("-- #{mode}")

      command = 'data-disassemble ' + args.join(' ')

      @postCommand command, (clazz, result) =>
        instructions = []
        if clazz == RESULT.DONE
          instructions = result.asm_insns.src_and_asm_line
        handler(instructions)

    insertBreak: ({location, condition, count, thread, temporary, hardware, disabled, tracepoint}, handler) ->
      args = []
      args.push('-t') if temporary is true
      args.push('-h') if hardware is true
      args.push('-d') if disabled is true
      args.push('-a') if tracepoint is true
      args.push("-c #{condition}") if condition
      args.push("-i #{count}") if count
      args.push("-p #{thread}") if thread
      args.push(location)

      command = 'break-insert ' + args.join(' ')

      @postCommand command, (clazz, result) =>
        abreak = null
        if clazz == RESULT.DONE
          abreak = result.bkpt
        handler(abreak)

    run: (handler) ->
      command = 'exec-run'
      @postCommand command, (clazz, result) =>
        handler(clazz == RESULT.RUNNING)

    continue: (handler) ->
      command = 'exec-continue'
      @postCommand command, (clazz, result) =>
        handler(clazz == RESULT.RUNNING)

    interrupt: (params, handler) ->
      command = 'exec-interrupt'
      handler = params if not handler
      @postCommand command, (clazz, result) =>
        handler(clazz == RESULT.DONE)

    next: (handler) ->
      command = 'exec-next'
      @postCommand command, (clazz, result) =>
        handler(clazz == RESULT.RUNNING)

    step: (handler) ->
      command = 'exec-step'
      @postCommand command, (clazz, result) =>
        handler(clazz == RESULT.RUNNING)

    finish: (handler) ->
      command = 'exec-finish'
      @postCommand command, (clazz, result) =>
        handler(clazz == RESULT.RUNNING)

    exit: (handler) ->
      command = 'gdb-exit'
      @postCommand command, (clazz, result) =>
        handler(clazz == RESULT.DONE)

    set: (key, value, handler) ->
      command = "gdb-set #{key} #{value}"
      @postCommand command, (clazz, result) =>
        handler(clazz == RESULT.DONE)

    target: (command, params, handler = (c,r) ->) ->
      if handler
        command = "target-#{command} #{params}"
      else
        command = "target-#{command}"
        handler = params
      @postCommand command, (clazz, result) =>
        handler(clazz == RESULT.DONE, result)

    stack: (command, params, handler = (c,r) ->) ->
      if handler
        command = "stack-#{command} #{params}"
      else
        command = "stack-#{command}"
        handler = params if params
      @postCommand command, (clazz, result) =>
        handler(clazz == RESULT.DONE, result)

    var: (command, params, handler = (c,r) ->) ->
      if handler
        command = "var-#{command} #{params}"
      else
        command = "var-#{command}"
        handler = params if params
      @postCommand command, (clazz, result) =>
        handler(clazz == RESULT.DONE, result)

    data: (command, params, handler = (c,r) ->) ->
      if handler
        command = "data-#{command} #{params}"
      else
        command = "data-#{command}"
        handler = params if params
      @postCommand command, (clazz, result) =>
        handler(clazz == RESULT.DONE, result)

    postCommand: (command, handler) ->
      @handler[@token] = handler
      @stdin.write("#{@token}-#{command}\n")
      @token = @token + 1
