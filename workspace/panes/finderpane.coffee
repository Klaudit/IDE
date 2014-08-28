class IDE.FinderPane extends IDE.Pane

  constructor: (options = {}, data) ->

    super options, data

    appManager  = KD.getSingleton 'appManager'
    computeCtrl = KD.getSingleton 'computeController'
    ideApp      = appManager.getFrontApp()

    appManager.open 'Finder', (finderApp) =>
      fc = @finderController = finderApp.create
        addAppTitle          : no
        bindMachineEvents    : no
        treeItemClass        : IDE.FinderItem

      @addSubView fc.getView()
      @bindListeners()

  bindListeners: ->
    mgr = KD.getSingleton 'appManager'
    fc  = @finderController

    fc.on 'FileNeedsToBeOpened', (file) ->
      file.fetchContents (err, contents) ->
        mgr.tell 'IDE', 'openFile', file, contents
        KD.getSingleton('windowController').setKeyView null

    fc.treeController.on 'TerminalRequested', (machine) ->
      mgr.tell 'IDE', 'openMachineTerminal', machine

    @on 'MachineMountRequested',   (machine) -> fc.mountMachine machine

    @on 'MachineUnmountRequested', (machine) -> fc.unmountMachine machine.uid
