@Crypto =
  SHA256: class extends Crypto.SHA256
    # defaults
    disableWorker: false
    workerSrc: '/packages/sha256/web-worker.js'
    chunkSize: 1024 * 32 # bytes

    constructor: (params) ->
      if params?
        if params.disableWorker?
          @disableWorker = params.disableWorker
        if params.workerSrc?
          @workerSrc = params.workerSrc
        if params.chunkSize?
          @chunkSize = params.chunkSize

      if !@disableWorker and typeof window != "undefined" and window.Worker
        @worker = new WebWorker @
      else
        @worker = new WorkerFallback @

    update: (params) ->
      params.message = 'update'
      if params.data instanceof Blob
        params.type = 'blob'
      else
        params.type = 'array'
      @worker.queue params

    finalize: (params) ->
      params.message = 'finalize'
      @worker.queue params

    _destroy: ->
      delete @worker

class BaseWorker
  constructor: (instance) ->
    self = @
    @chunkStart = 0
    @totalSize = 0
    @busy = false
    @buffer = []
    @current = null
    @reader = null
    @instance = instance

    @handler =
      progress: (progress) ->
        # progress is undefined
        progress = self.chunkStart / self.totalSize
        self.current?.onProgress? progress
        self.flush(true)
        
      done: (sha256) ->
        self.current?.onDone? sha256
        self.destroy()

  destroy: ->
    @instance._destroy()

  queue: (params) ->
    @buffer.push params
    @flush(false)

  flush: (progress) ->
    # return if worker is busy and isn't called by onProgress
    return if not progress and @busy
    @busy = true
    # if current chunk is processed completely
    if @chunkStart >= @totalSize
      @chunkStart = 0
      @totalSize = 0
      @current = @buffer.shift()
      if !@current
        return @busy = false
      if @current.message == 'update'
        if @current.type == 'blob'
          @totalSize = @current.data.size
          if not @reader
            @setupFileReader()
        else
          @totalSize = @current.data.byteLength
    
    # check if it's finalize command
    if @current.message == 'finalize'
      @finalize()
      return

    # flush next chunk
    start = @chunkStart
    end = start + @instance.chunkSize
    if end > @totalSize
      end = @totalSize
    @chunkStart = end
    chunk = @current.data.slice start, end
    if @current.type == 'blob'
      @reader.readAsArrayBuffer chunk
    else
      @processChunk chunk

  processChunk: (chunk) ->
    throw new Error "Not implemented!"

  setupFileReader: ->
    self = @
    @reader = new FileReader()
    @reader.onload = ->
      self.processChunk @result
      #self.handler.progress Math.min(self.chunkStart, self._fileSize) / self._fileSize
      #self._readNext()
    #self._readNext()

class WebWorker extends BaseWorker
  constructor: (instance) ->
    super instance

    @worker = new Worker instance.workerSrc
    self = @
    @worker.onmessage = (oEvent) ->
      data = oEvent.data.data
      message = oEvent.data.message
      self.handler[message] data

  processChunk: (data) ->
    @worker.postMessage
      chunk: data,
      message: 'update'

  finalize: ->
    @worker.postMessage
      message: 'finalize'

  destroy: ->
    @worker.terminate()
    super


class WorkerFallback extends BaseWorker
  constructor: (instance) ->
    super instance
    @hash = new Digest.SHA256

  _bin2hex: (array) ->
    hexTab = '0123456789abcdef'
    str = ''
    for a in array
      str += hexTab.charAt((a >>> 4) & 0xF) + hexTab.charAt(a & 0xF)
    str

  processChunk: (data) ->
    @hash.update data
    @handler.progress()

  finalize: ->
    binaryData = @hash.finalize()
    fin = new Uint8Array binaryData
    sha256 = @_bin2hex fin
    @handler.done sha256

  destroy: ->
    super