class IDE.DrawingPane extends IDE.Pane


  penSizes = [ 3, 5, 8, 12, 15, 20 ]
  colors   = [ '#CD3A33', '#7B9D60', '#D7BB29', '#62ABB6', '#BC66A7', '#726AB0' ]


  constructor: (options = {}, data) ->

    options.cssClass = KD.utils.curry 'drawing-pane', options.cssClass
    options.paneType = 'drawing'

    super options, data


  createCanvas: ->
    @canvas      = new KDCustomHTMLView
      tagName    : 'canvas'
      attributes :
        width    : @getWidth()
        height   : @getHeight()

    @addSubView @canvas


  createToolbar: ->
    @toolbar  = new KDCustomHTMLView cssClass: 'drawing-board-toolbar'
    commands  =
      undo    : action : 'undo'
      redo    : action : 'redo'
      clear   : action : 'clear'
      penSize : action : 'showPenSizes'
      color   : action : 'showColors'
      save    : action : 'save'


    for command, config of commands
      @toolbar.addSubView view = new KDCustomHTMLView
        cssClass : "item #{command}"
        partial  : "<p class='icon'></p>"
        click    : @bound config.action

      @colorMenuView   = view  if command is 'color'
      @penSizeMenuView = view  if command is 'penSize'

    @addSubView @toolbar

    @colorMenuView.on   'click', =>
      @penSizeMenuView.unsetClass 'selected'
      @colorMenuView.setClass     'selected'

    @penSizeMenuView.on 'click', =>
      @penSizeMenuView.setClass 'selected'
      @colorMenuView.unsetClass 'selected'


  showPenSizes: ->
    items = []

    penSizes.forEach (size) =>
      items.push new KDCustomHTMLView
        cssClass : 'item pen-size'
        partial  : "<div style='width: #{size}px; height: #{size}px; margin: -#{size/2}px 0 0 -#{size/2}px'></div>"
        click    : => @handlePenSizeChange size

    @createToolbarMenu items


  showColors: ->
    items  = []

    colors.forEach (color) =>
      items.push new KDCustomHTMLView
        cssClass : 'item color'
        partial  : "<div style='background-color: #{color}'></div>"
        click    : => @handleColorChange color

    @createToolbarMenu items


  createToolbarMenu: (items) ->
    @toolbarMenu?.destroy()

    @addSubView @toolbarMenu = new KDCustomHTMLView
      cssClass : 'drawing-board-toolbar menu'

    @toolbarMenu.addSubView item  for item in items

    @addLayerForMenu()


  init: ->
    @$canvas = @canvas.getDomElement()
    @$canvas.sketchpad
      aspectRatio : 1
      canvasColor : '#2B2B2B'

    @$canvas.setLineSize  3
    @$canvas.setLineColor colors.first


  addLayerForMenu: ->
    KD.getSingleton('windowController').addLayer @toolbarMenu

    @toolbarMenu.once 'ReceivedClickElsewhere', =>
      @toolbarMenu.destroy()
      @penSizeMenuView.unsetClass 'selected'
      @colorMenuView.unsetClass 'selected'


  handleColorChange: (color) ->
    @setPenColor color
    @colorMenuView.updatePartial "<p class='icon' style='background-color:#{color}'></p>"
    @colorMenuView.unsetClass 'selected'
    @toolbarMenu.destroy()


  handlePenSizeChange: (size) ->
    @setPenSize size
    @penSizeMenuView.unsetClass 'selected'
    @toolbarMenu.destroy()


  redo: -> @$canvas.redo()


  undo: -> @$canvas.undo()


  setPenColor: (color) -> @$canvas.setLineColor color


  getPenColor: -> return @$canvas.getLineColor()


  setPenSize: (size) -> return @$canvas.setLineSize size


  getPenSize: -> return @$canvas.getLineSize()


  getCanvasData: -> return @$canvas.json()


  setCanvasData: (json) -> @$canvas.jsonLoad json


  clear: -> @$canvas.clear()


  save: ->
    new KDNotificationView
      title: 'Saving will be enabled soon.'


  serialize: ->
    return data: @getCanvasData()


  viewAppended: ->
    super

    @createCanvas()
    @createToolbar()
    @init()
