class IDE.EditorPane extends IDE.Pane

  shortcutsShown = no

  constructor: (options = {}, data) ->

    options.cssClass = KD.utils.curry 'editor-pane', options.cssClass
    options.paneType = 'editor'

    {file} = options
    @file  = file

    super options, data

    @hash  = file.paneHash  if file.paneHash

    @on 'SaveRequested', @bound 'save'

    @lineWidgets = {}
    @cursors     = {}

    @createEditor()

    file.once 'fs.delete.finished', =>
      KD.getSingleton('appManager').tell 'IDE', 'handleFileDeleted', file

    @once 'RealTimeManagerSet', @bound 'listenCollaborativeStringChanges'

  createEditor: ->
    {file, content} = @getOptions()

    unless file instanceof FSFile
      throw new TypeError 'File must be an instance of FSFile'

    unless content?
      throw new TypeError 'You must pass file content to IDE.EditorPane'

    aceOptions =
      delegate                 : @getDelegate()
      createBottomBar          : no
      createFindAndReplaceView : no

    @addSubView @aceView = new AceView aceOptions, file

    {ace} = @aceView

    ace.once 'ace.ready', =>
      @getEditor().setValue content, 1
      ace.setReadOnly yes  if @getOptions().readOnly
      @bindChangeListeners()
      @emit 'EditorIsReady'

      KD.singletons.appManager.tell 'IDE', 'setRealTimeManager', this

  save: ->
    ace.emit 'ace.requests.save', @getContent()

  getAce: ->
    return @aceView.ace

  getEditor: ->
    return @getAce().editor

  getEditorSession: ->
    return @getEditor().getSession()

  getValue: ->
    return  @getEditorSession().getValue()

  goToLine: (lineNumber) ->
    @getAce().gotoLine lineNumber

  setFocus: (state) ->
    super state

    return  unless ace = @getEditor()

    if state
    then ace.focus()
    else ace.blur()

  getContent: ->
    return @getAce().getContents()

  setContent: (content, emitFileContentChangedEvent = yes) ->
    @getAce().setContent content, emitFileContentChangedEvent

  getCursor: ->
    return @getEditor().selection.getCursor()

  setCursor: (positions) ->
    @getEditor().selection.moveCursorTo positions.row, positions.column

  getFile: ->
    return @aceView.getData()

  bindChangeListeners: ->
    ace           = @getAce()
    change        =
      origin      : KD.nick()
      context     :
        paneHash  : @hash
        paneType  : @getOptions().paneType
        file      :
          path    : @file.path
          machine :
            uid   : @file.machine.uid

    ace.on 'ace.change.cursor', (cursor) =>
      change.type = 'CursorActivity'
      change.context.cursor = cursor

      @emit 'ChangeHappened', change

    ace.on 'FileContentChanged', =>
      return if @dontEmitChangeEvent

      change.type = 'ContentChange'
      change.context.file.content = @getContent()

      @emit 'ChangeHappened', change

  serialize: ->
    file       = @getFile()
    {paneType} = @getOptions()
    {machine}  = file

    {name, path } = file
    {label, ipAddress, slug, uid} = machine

    data       =
      file     : { name, path }
      machine  : { label, ipAddress, slug, uid }
      paneType : paneType
      hash     : @hash

    return data


  setLineWidgets: (row, col, username) ->
    oldWidget      = @lineWidgets[username]
    oldCursor      = @cursors[username]
    {renderer}     = @getEditor()
    widgetManager  = @getAce().lineWidgetManager
    lineHeight     = renderer.lineHeight
    charWidth      = renderer.characterWidth
    color          = KD.utils.getColorFromString username
    widgetStyle    = "border-bottom:2px dotted #{color};height:#{lineHeight}px;margin-top:-#{lineHeight+2}px;"
    lineCssClass   = "ace-line-widget ace-line-widget-#{KD.nick()}"
    cursorCssClass = 'ace-participant-cursor'
    cursorStyle    = "background-color:#{color};height:#{lineHeight}px;margin-left:#{charWidth*col+3}px"
    lineWidgetHTML = """
      <div class='#{lineCssClass}' style='#{widgetStyle}'>
        <span class="username">#{username}</span>
        <span class="#{cursorCssClass}" style="#{cursorStyle}"></span>
      </div>
    """

    if oldWidget
      widgetManager.removeLineWidget oldWidget

    $(".ace-line-widget-#{KD.nick()}").remove()

    lineWidgetOptions =
      row        : row
      rowCount   : 0
      fixedWidth : yes
      editor     : @getEditor()
      html       : lineWidgetHTML

    KD.utils.defer =>
      widgetManager.addLineWidget lineWidgetOptions
      @lineWidgets[username] = lineWidgetOptions


  handleChange: (change, rtm, realTimeDoc) ->
    {context, type, origin} = change

    if type is 'CursorActivity'
      {row, column} = context.cursor
      @setLineWidgets row, column, origin


  listenCollaborativeStringChanges: ->
    filePath = @getFile().path

    return if filePath.indexOf('localfile:/') > -1

    string = @rtm.getFromModel filePath

    @setContent string.getText(), no

    return unless string

    @rtm.bindRealtimeListeners string, 'string'

    @rtm.on 'TextInsertedIntoString', (changedString, change) =>
      if changedString is string
        return if @isChangedByMe change

        @applyChange change

    @rtm.on 'TextDeletedFromString', (changedString, change) =>
      if changedString is string
        return if @isChangedByMe change

        @applyChange change


  isChangedByMe: (change) ->
    for collaborator in @rtm.getCollaborators() when collaborator.isMe
      me = collaborator

    return me.sessionId is change.sessionId


  getRange: (index, length, str) ->
    start   = index
    end     = index + length
    lines   = str.split "\n"
    read    = 0
    points  =
      start : row: 0, column: 0
      end   : row: 0, column: 0

    for line in lines when read <= index
      read                += line.length + 1
      offset               = read - 1 - index
      points.start.row    += 1
      points.start.column  = line.length - offset  if read > index

    points.end.row    = points.start.row
    points.end.column = points.start.column + end - index

    for lineIndex in [points.start.row...lines.length] when read <= end
      line               = lines[lineIndex]
      read              += line.length + 1
      offset             = read - 1 - end
      points.end.row    += 1
      points.end.column  = line.length - offset  if read > end

    points.start.row -= 1
    points.end.row   -= 1

    return points


  applyChange: (change) ->
    isInserted = change.type is 'text_inserted'
    isDeleted  = change.type is 'text_deleted'
    range      = @getRange change.index, change.text.length, @getContent()

    @dontEmitChangeEvent = yes

    if isInserted
      @getEditorSession().insert range.start, change.text

    else if isDeleted
      @getEditorSession().remove range

    @dontEmitChangeEvent = no
