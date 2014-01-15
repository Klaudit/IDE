class NFinderTreeController extends JTreeViewController

  constructor:->

    super

    if @getOptions().contextMenu
      @contextMenuController = new NFinderContextMenuController

      @contextMenuController.on "ContextMenuItemClicked", ({fileView, contextMenuItem})=>
        @contextMenuItemSelected fileView, contextMenuItem
    else
      @getView().setClass "no-context-menu"

    @appManager    = KD.getSingleton "appManager"
    mainController = KD.getSingleton "mainController"

    mainController.on "NewFileIsCreated", @bound "navigateToNewFile"
    mainController.on "SelectedFileChanged", @bound "highlightFile"

  addNode:(nodeData, index)->

    fc = @getDelegate()
    return if @getOption('foldersOnly') and nodeData.type is "file"
    return if nodeData.isHidden() and fc.isNodesHiddenFor nodeData.vmName
    item = super nodeData, index

  highlightFile:(view)->

    @selectNode @nodes[view.data.path], null, no

    if view.ace?
      if view.ace.editor?
        view.ace.editor.focus()
      else
        view.ace.on "ace.ready", ->
          view.ace.editor.focus()

  navigateToNewFile:(newFile)->

    @navigateTo newFile.parentPath, =>
      @selectNode @nodes[newFile.path]

  getOpenFolders: ->

    return Object.keys(@listControllers).slice(1)

  ###
  FINDER OPERATIONS
  ###

  openItem:(nodeView, callback)->

    options  = @getOptions()
    nodeData = nodeView.getData()

    switch nodeData.type
      when "folder", "mount", "vm"
        @toggleFolder nodeView, callback
      when "file"
        @openFile nodeView
        @emit "file.opened", nodeData
        @setBlurState()

  # openFileWithApp: (nodeView, contextMenuItem) ->
  #   return warn "no app passed to open this file"  unless contextMenuItem
  #   app = contextMenuItem.getData().title
  #   KD.getSingleton("appManager").openFileWithApplication app, nodeView.getData()

  openFile:(nodeView)->

    return unless nodeView
    file = nodeView.getData()
    # @appManager.openFile file
    @getDelegate().emit "FileNeedsToBeOpened", file

  previewFile:(nodeView)->
    {vmName, path} = nodeView.getData()
    @appManager.open "Viewer", params: {path, vmName}

  resetVm:(nodeView)->
    {vmName} = nodeView.data
    KD.getSingleton('vmController').reinitialize vmName

  unmountVm:(nodeView)->
    {vmName} = nodeView.data
    @getDelegate().unmountVm vmName

  openVmTerminal:(nodeView)->
    {vmName} = nodeView.data
    @appManager.open "Terminal", params: {vmName}, forceNew: yes

  toggleDotFiles:(nodeView)->

    finder         = @getDelegate()
    {vmName, path} = nodeView.getData()

    if finder.isNodesHiddenFor vmName
    then finder.showDotFiles vmName
    else finder.hideDotFiles vmName

  makeTopFolder:(nodeView)->
    {vmName, path} = nodeView.getData()
    finder = @getDelegate()
    finder.updateVMRoot vmName, FSHelper.plainPath path

  refreshFolder:(nodeView, callback)->

    @notify "Refreshing..."
    folder = nodeView.getData()
    folder.emit "fs.job.finished", [] # in case of refresh to stop the spinner

    @collapseFolder nodeView, =>
      @expandFolder nodeView, =>
        notification.destroy()
        callback?()

  toggleFolder:(nodeView, callback)->
    if nodeView.expanded
      @collapseFolder nodeView, callback
    else
      @expandFolder nodeView, callback

  expandFolder:(nodeView, callback, silence=no)->

    return unless nodeView
    return if nodeView.isLoading

    if nodeView.expanded
      callback? null, nodeView
      return

    folder = nodeView.getData()

    if folder.depth > 10
      @notify "Folder is nested deeply, making it top folder"
      @makeTopFolder nodeView

    failCallback = (err)=>
      unless silence
        if err?.message?.match /permission denied/i
          message = "Permission denied!"
          KD.logToExternal "filetree: Couldn't fetch files, permission denied"
        else
          message = "Couldn't fetch files! Click to retry"
          KD.logToExternalWithTime "filetree: Couldn't fetch files"
        @notify message, 'clickable', \
                """Sorry, a problem occured while communicating with servers,
                   please try again later.""", yes
        @once 'fs.retry.scheduled', => @expandFolder nodeView, callback
      folder.emit "fs.job.finished", []
      callback? err

    folder.fetchContents (KD.utils.getTimedOutCallback (err, files)=>
      unless err
        nodeView.expand()
        if files
          @addNodes files
        callback? null, nodeView
        @emit "folder.expanded", nodeView.getData()  unless silence
        @emit 'fs.retry.success'
        @hideNotification()
      else
        failCallback err
    , failCallback, KD.config.fileFetchTimeout), no

  collapseFolder:(nodeView, callback, silence=no)->

    return unless nodeView
    folder = nodeView.getData()
    {path} = folder

    @emit "folder.collapsed", folder  unless silence

    if @listControllers[path]
      @listControllers[path].getView().collapse =>
        @removeChildNodes path
        nodeView.collapse()
        callback? nodeView
    else
      nodeView.collapse()
      callback? nodeView

  navigateTo:(path, callback)->

    return unless path

    path = path.split('/')
    path.shift()  if path[0] is ''
    path.pop()    if path[path.length-1] is ''
    path[1] = "/#{path[0]}/#{path[1]}"
    path.shift()

    index     = 0
    lastPath  = ''

    _expand = (path)=>
      nextPath = path.slice(0, ++index).join('/')
      if lastPath is nextPath
        @refreshFolder @nodes[nextPath], =>
          callback?()
        return

      @expandFolder @nodes[nextPath], =>
        lastPath = nextPath
        _expand path

    _expand path

  confirmDelete:(nodeView, event)->

    extension = nodeView.data?.getExtension() or null

    if @selectedNodes.length > 1
      new NFinderDeleteDialog {},
        items     : @selectedNodes
        callback  : (confirmation)=>
          @deleteFiles @selectedNodes if confirmation
          @setKeyView()
    else
      @beingEdited = nodeView
      nodeView.confirmDelete (confirmation)=>
        @deleteFiles [nodeView] if confirmation
        @setKeyView()
        @beingEdited = null

  deleteFiles:(nodes, callback)->

    stack = []
    nodes.forEach (node)=>
      stack.push (cb) =>
        node.getData().remove (err, response)=>
          if err then @notify null, null, err
          else
            node.emit "ItemBeingDeleted"
            cb err, node

    async.parallel stack, (error, result) =>
      @notify "#{result.length} item#{if result.length > 1 then 's' else ''} deleted!", "success"
      @removeNodeView node for node in result
      callback?()


  showRenameDialog:(nodeView)->

    @beingEdited = nodeView
    nodeData = nodeView.getData()
    oldPath = nodeData.path
    nodeView.showRenameView (newValue)=>
      return if newValue is nodeData.name
      if @nodes["#{nodeData.parentPath}/#{newValue}"]
        caretPos = nodeView.renameView.input.getCaretPosition()
        @notify "#{nodeData.type.capitalize()} exist!", "error"
        return KD.utils.defer =>
          @showRenameDialog nodeView
          nodeView.renameView.input.setCaretPosition caretPos

      nodeData.rename newValue, (err)=>
        if err then @notify null, null, err
        # else
        #   delete @nodes[oldPath]
        #   @nodes[nodeView.getData().path] = nodeView
        #   nodeView.childView.render()

      # @setKeyView()
      @beingEdited = null

  createFile:(nodeView, type = "file")->
    @notify "creating a new #{type}!"
    nodeData = nodeView.getData()
    {vmName} = nodeData

    if nodeData.type is "file"
      {parentPath} = nodeData
    else
      parentPath = nodeData.path

    path = FSHelper.plainPath \
      "#{parentPath}/New#{type.capitalize()}#{if type is 'file' then '.txt' else ''}"

    FSItem.create { path, type, vmName, treeController: this }, (err, file)=>
      if err
        @notify null, null, err
      else
        @refreshFolder @nodes[parentPath], =>
          @notify "#{type} created!", "success"
          node = @nodes["[#{file.vmName}]#{file.path}"]
          @selectNode node
          @showRenameDialog node


  moveFiles:(nodesToBeMoved, targetNodeView, callback)->

    targetItem = targetNodeView.getData()
    if targetItem.type is "file"
      targetNodeView = @nodes[targetNodeView.getData().parentPath]
      targetItem = targetNodeView.getData()

    stack = []
    nodesToBeMoved.forEach (node)=>
      stack.push (cb) =>
        sourceItem = node.getData()
        FSItem.move sourceItem, targetItem, (err, response)=>
          if err then @notify null, null, err
          else
            cb err, node

    callback or= (error, result) =>
      @notify "#{result.length} item#{if result.length > 1 then 's' else ''} moved!", "success"
      @removeNodeView node for node in result
      @refreshFolder targetNodeView

    async.parallel stack, callback

  copyFiles:(nodesToBeCopied, targetNodeView, callback)->

    targetItem = targetNodeView.getData()
    if targetItem.type is "file"
      targetNodeView = @nodes[targetNodeView.getData().parentPath]
      targetItem = targetNodeView.getData()

    stack = []
    nodesToBeCopied.forEach (node)=>
      stack.push (cb) =>
        sourceItem = node.getData()
        FSItem.copy sourceItem, targetItem, (err, response)=>
          if err then @notify null, null, err
          else
            cb err, node

    callback or= (error, result) =>
      @notify "#{result.length} item#{if result.length > 1 then 's' else ''} copied!", "success"
      @refreshFolder targetNodeView

    async.parallel stack, callback

  duplicateFiles:(nodes, callback)->

    stack = []
    nodes.forEach (node)=>
      stack.push (cb) =>
        sourceItem = node.getData()
        targetItem = @nodes[sourceItem.parentPath].getData()
        FSItem.copy sourceItem, targetItem, (err, response)=>
          if err then @notify null, null, err
          else
            cb err, node

    callback or= (error, result) =>
      @notify "#{result.length} item#{if result.length > 1 then 's' else ''} duplicated!", "success"
      parentNodes = []
      result.forEach (node)=>
        parentNode = @nodes[node.getData().parentPath]
        parentNodes.push parentNode unless parentNode in parentNodes
      @refreshFolder parentNode for parentNode in parentNodes

    async.parallel stack, callback

  compressFiles:(nodeView, type)->

    file = nodeView.getData()
    FSItem.compress file, type, (err, response)=>
      if err then @notify null, null, err
      else
        @notify "#{file.type.capitalize()} compressed!", "success"
        @refreshFolder @nodes[file.parentPath]

  extractFiles:(nodeView)->

    file = nodeView.getData()
    FSItem.extract file, (err, response)=>
      if err then @notify null, null, err
      else
        @notify "#{file.type.capitalize()} extracted!", "success"
        @refreshFolder @nodes[file.parentPath], =>
          @selectNode @nodes[response.path]

  # compileApp:(nodeView, callback)->

  #   folder = nodeView.getData()
  #   folder.emit "fs.job.started"
  #   kodingAppsController = KD.getSingleton('kodingAppsController')

  #   manifest = KodingAppsController.getManifestFromPath folder.path

  #   kodingAppsController.compileApp manifest.name, (err)=>
  #     folder.emit "fs.job.finished"
  #     if not err
  #       @notify "App compiled!", "success"
  #       @utils.wait 500, =>
  #         @refreshFolder nodeView, =>
  #           @utils.defer =>
  #             @selectNode @nodes["#{folder.path}/index.js"]
  #     callback? err

  # runApp:(nodeView, callback)->

  #   folder = nodeView.getData()
  #   folder.emit "fs.job.started"
  #   kodingAppsController = KD.getSingleton 'kodingAppsController'

  #   manifest = KodingAppsController.getManifestFromPath folder.path

  #   KD.getSingleton("appManager").open manifest.name, =>
  #     folder.emit "fs.job.finished"
  #     callback?()

  cloneRepo: (nodeView) ->
    folder   = nodeView.getData()
    modal    = new CloneRepoModal
      vmName : folder.vmName
      path   : folder.path
    modal.on "RepoClonedSuccessfully", => @notify "Repo cloned successfully.", "success"

  # publishApp:(nodeView)->

  #   folder = nodeView.getData()

  #   folder.emit "fs.job.started"
  #   KD.getSingleton('kodingAppsController').publishApp folder.path, (err)=>
  #     folder.emit "fs.job.finished"
  #     unless err
  #       @notify "App published!", "success"
  #     else
  #       @notify "Publish failed!", "error", err
  #       message = err.message or err
  #       modal = new KDModalView
  #         title        : "Publish failed!"
  #         overlay      : yes
  #         cssClass     : "new-kdmodal"
  #         content      : "<div class='modalformline'>#{message}</div>"
  #         buttons      :
  #           "Close"    :
  #             style    : "modal-clean-gray"
  #             callback : (event)->
  #               modal.destroy()

  # makeNewApp:(nodeView)->
  #   KD.getSingleton('kodingAppsController').makeNewApp()

  # downloadAppSource:(nodeView)->

  #   folder = nodeView.getData()

  #   folder.emit "fs.job.started"
  #   KD.getSingleton('kodingAppsController').downloadAppSource folder.path, (err)=>
  #     folder.emit "fs.job.finished"
  #     @refreshFolder @nodes[folder.parentPath]
  #     unless err
  #       @notify "Source downloaded!", "success"
  #     else
  #       @notify "Download failed!", "error", err

  openTerminalFromHere: (nodeView) ->
    @appManager.open "Terminal", (appInstance) =>
      path          = nodeView.getData().path
      {terminalView} = @appManager.getFrontApp().getView().tabView.getActivePane().getOptions()

      terminalView.on "WebTermConnected", (server) =>
        server.input "cd #{path}\n"

  ###
  CONTEXT MENU OPERATIONS
  ###

  cmExpand:        (nodeView, contextMenuItem)-> @expandFolder node for node in @selectedNodes
  cmCollapse:      (nodeView, contextMenuItem)-> @collapseFolder node for node in @selectedNodes # error fix this
  cmMakeTopFolder: (nodeView, contextMenuItem)-> @makeTopFolder nodeView
  cmRefresh:       (nodeView, contextMenuItem)-> @refreshFolder nodeView
  cmToggleDotFiles:(nodeView, contextMenuItem)-> @toggleDotFiles nodeView
  cmResetVm:       (nodeView, contextMenuItem)-> @resetVm nodeView
  cmUnmountVm:     (nodeView, contextMenuItem)-> @unmountVm nodeView
  cmOpenVmTerminal:(nodeView, contextMenuItem)-> @openVmTerminal nodeView
  cmCreateFile:    (nodeView, contextMenuItem)-> @createFile nodeView
  cmCreateFolder:  (nodeView, contextMenuItem)-> @createFile nodeView, "folder"
  cmRename:        (nodeView, contextMenuItem)-> @showRenameDialog nodeView
  cmDelete:        (nodeView, contextMenuItem)-> @confirmDelete nodeView
  cmDuplicate:     (nodeView, contextMenuItem)-> @duplicateFiles @selectedNodes
  cmExtract:       (nodeView, contextMenuItem)-> @extractFiles nodeView
  cmZip:           (nodeView, contextMenuItem)-> @compressFiles nodeView, "zip"
  cmTarball:       (nodeView, contextMenuItem)-> @compressFiles nodeView, "tar.gz"
  cmUpload:        (nodeView, contextMenuItem)-> @uploadFile nodeView
  cmDownload:      (nodeView, contextMenuItem)-> @appManager.notify()
  cmGitHubClone:   (nodeView, contextMenuItem)-> @appManager.notify()
  cmOpenFile:      (nodeView, contextMenuItem)-> @openFile nodeView
  cmPreviewFile:   (nodeView, contextMenuItem)-> @previewFile nodeView
  # cmCompile:       (nodeView, contextMenuItem)-> @compileApp nodeView
  # cmRunApp:        (nodeView, contextMenuItem)-> @runApp nodeView
  # cmMakeNewApp:    (nodeView, contextMenuItem)-> @makeNewApp nodeView
  # cmDownloadApp:   (nodeView, contextMenuItem)-> @downloadAppSource nodeView
  # cmPublish:       (nodeView, contextMenuItem)-> @publishApp nodeView
  cmOpenFileWithApp: (nodeView, contextMenuItem)-> @openFileWithApp  nodeView, contextMenuItem
  cmCloneRepo:     (nodeView, contextMenuItem)-> @cloneRepo nodeView
  cmDropboxChooser:(nodeView, contextMenuItem)-> @chooseFromDropbox nodeView
  cmDropboxSaver:  (nodeView, contextMenuItem)-> __saveToDropbox nodeView
  cmOpenTerminal:  (nodeView, contextMenuItem)-> @openTerminalFromHere nodeView
  # cmShowOpenWithModal: (nodeView, contextMenuItem)-> @showOpenWithModal nodeView
  # cmOpenFileWithApp: (nodeView, contextMenuItem)-> @openFileWithApp  nodeView, contextMenuItem

  cmOpenFileWithCodeMirror:(nodeView, contextMenuItem)-> @appManager.notify()

  ###
  CONTEXT MENU CREATE/MANAGE
  ###

  createContextMenu:(nodeView, event)->

    event.stopPropagation()
    event.preventDefault()
    return if nodeView.beingDeleted or nodeView.beingEdited

    if nodeView in @selectedNodes
      contextMenu = @contextMenuController.getContextMenu @selectedNodes, event
    else
      @selectNode nodeView
      contextMenu = @contextMenuController.getContextMenu [nodeView], event
    no

  contextMenuItemSelected:(nodeView, contextMenuItem)->

    {action} = contextMenuItem.getData()
    if action
      if @["cm#{action.capitalize()}"]?
        @contextMenuController.destroyContextMenu()
      @["cm#{action.capitalize()}"]? nodeView, contextMenuItem

  ###
  RESET STATES
  ###

  resetBeingEditedItems:->

    @beingEdited.resetView()

  organizeSelectedNodes:(listController, nodes, event = {})->

    @resetBeingEditedItems() if @beingEdited
    super

  ###
  DND UI FEEDBACKS
  ###

  showDragOverFeedback:(nodeView, event)-> super

  clearDragOverFeedback:(nodeView, event)-> super

  clearAllDragFeedback:-> super

  ###
  HANDLING MOUSE EVENTS
  ###

  click:(nodeView, event)->

    if $(event.target).is ".chevron"
      @contextMenu nodeView, event
      return no

    if $(event.target).is ".arrow"
      @openItem nodeView
      return no

    super

  dblClick:(nodeView, event)->

    @openItem nodeView

  contextMenu:(nodeView, event)->

    if @getOptions().contextMenu
      @createContextMenu nodeView, event

  ###
  HANDLING DND
  ###

  dragOver: (nodeView, event)->

    @showDragOverFeedback nodeView, event
    super

  dragStart: (nodeView, event)->
    super

    @internalDragging = yes

    {name, vmName, path} = nodeView.data

    warningText = """
    You should move #{name} file to Web folder to download using drag and drop. -- Koding
    """

    type        = "application/octet-stream"
    url         = KD.getPublicURLOfPath path
    unless url
      url       = "data:#{type};base64,#{btoa warningText}"
      name     += ".txt"
    dndDownload = "#{type}:#{name}:#{url}"

    event.originalEvent.dataTransfer.setData 'DownloadURL', dndDownload

  lastEnteredNode = null
  dragEnter: (nodeView, event)->

    return nodeView if lastEnteredNode is nodeView or nodeView in @selectedNodes
    lastEnteredNode = nodeView
    clearTimeout @expandTimeout
    if nodeView.getData().type in ["folder","mount","vm"]
      @expandTimeout = setTimeout (=> @expandFolder nodeView), 800
    @showDragOverFeedback nodeView, event
    e = event.originalEvent

    if @boundaries.top > e.pageY > @boundaries.top + 20
      log "trigger top scroll"

    if @boundaries.top + @boundaries.height < e.pageY < @boundaries.top + @boundaries.height + 20
      log "trigger down scroll"

    super


  dragLeave: (nodeView, event)->

    @clearDragOverFeedback nodeView, event
    super

  dragEnd: (nodeView, event)->

    # log "clear after drag"
    @clearAllDragFeedback()
    @internalDragging = no
    super

  drop: (nodeView, event)->

    return if nodeView in @selectedNodes
    return unless nodeView.getData?().type in ['folder', 'mount', 'vm']

    @selectedNodes = @selectedNodes.filter (node)->
      targetPath = nodeView.getData?().path
      sourcePath = node.getData?().parentPath

      return targetPath isnt sourcePath

    if event.altKey
      @copyFiles @selectedNodes, nodeView
    else
      @moveFiles @selectedNodes, nodeView

    @internalDragging = no
    super

  ###
  HANDLING KEY EVENTS
  ###

  keyEventHappened:(event)->

    super

  performDownKey:(nodeView, event)->

    if event.altKey
      offset = nodeView.$('.chevron').offset()
      event.pageY = offset.top
      event.pageX = offset.left
      @contextMenu nodeView, event
    else
      super

  performBackspaceKey:(nodeView, event)->

    event.preventDefault()
    event.stopPropagation()
    @confirmDelete nodeView, event
    no

  performEnterKey:(nodeView, event)->

    @selectNode nodeView
    @openItem nodeView

  performRightKey:(nodeView, event)->

    {type} = nodeView.getData()
    if /mount|folder|vm/.test type
      @expandFolder nodeView

  performUpKey:(nodeView, event)-> super
  performLeftKey:(nodeView, event)->

    if nodeView.expanded
      @collapseFolder nodeView
      return no
    super


  ###
  HELPERS
  ###

  notification  = null
  autoTriedOnce = yes

  hideNotification: ->
    notification.destroy() if notification

  notify:(msg, style, details, reconnect=no)->

    return unless @getView().parent?

    notification.destroy() if notification

    if details and not msg and /Permission denied/i.test details?.message
      msg = "Permission denied!"

    style or= 'error' if details
    duration = if reconnect then 0 else if details then 5000 else 2500

    notification = new KDNotificationView
      title     : msg or "Something went wrong"
      type      : "finder-notification"
      cssClass  : "#{style}"
      container : @getView().parent
      # duration  : 0
      duration  : duration
      details   : details
      click     : =>
        if reconnect
          @emit 'fs.retry.scheduled'
          notification.notificationSetTitle 'Attempting to fetch files'
          notification.notificationSetPositions()
          notification.setClass 'loading'

          @utils.wait 6000, notification.bound "destroy"
          @once 'fs.retry.success', notification.bound "destroy"
          return

        if notification.getOptions().details
          details = new KDNotificationView
            title     : "Error details"
            content   : notification.getOptions().details
            type      : "growl"
            duration  : 0
            click     : -> details.destroy()

          KD.getSingleton('windowController').addLayer details
          details.on 'ReceivedClickElsewhere', ->
            details.destroy()

  refreshTopNode:->
    {nickname} = KD.whoami().profile
    @refreshFolder @nodes["/home/#{nickname}"], => @emit "fs.retry.success"

  # showOpenWithModal: (nodeView) ->
  #   KD.getSingleton("kodingAppsController").fetchApps (err, apps) =>
  #     new OpenWithModal {}, {
  #       nodeView
  #       apps
  #     }

  chooseFromDropbox: (nodeView) ->
    fileItemViews     = []
    filePath          = FSHelper.plainPath nodeView.getData().path
    modal             = null
    kallback          = ->
      file            = fileItemViews[0]
      if file
        file.emit "FileNeedsToBeDownloaded", filePath
        file.on   "FileDownloadDone", ->
          fileItemViews.shift()
          if fileItemViews.length
            kallback()
          else
            modal.destroy()
            new KDNotificationView
              title    : "Your download has been completed"
              type     : "mini"
              cssClass : "success"
              duration : 4000

    Dropbox.choose
      linkType         : "direct"
      multiselect      : true
      success          : (files) ->
        modal          = new KDModalView
          overlay      : yes
          title        : "Download from Dropbox"
          buttons      :
            Start      :
              title    : "Start"
              cssClass : "modal-clean-green"
              callback : -> kallback()
            Cancel     :
              title    : "Cancel"
              cssClass : "modal-cancel"
              callback : -> modal.destroy()

        for file in files
          fileItemView = modal.addSubView new DropboxDownloadItemView { nodeView }, file
          fileItemViews.push fileItemView

  uploadFile: (nodeView)->
    finderController = @getDelegate()
    {path} = nodeView.data
    finderController.uploadTo path  if path
