class NVMItemView extends NFileItemView

  constructor:(options = {},data)->

    options.cssClass or= "vm"
    super options, data

    @vm = KD.getSingleton 'vmController'
    @vm.on 'StateChanged', @bound 'checkVMState'

    @folderSelector = new KDSelectBox
      selectOptions : @createSelectOptions()
      callback      : (path) =>
        data        = @getData()
        vm          = data.vmName
        finder      = data.treeController.getDelegate()

        finder?.updateVMRoot vm, path

    @vmInfo    = new KDCustomHTMLView
      tagName  : 'span'
      cssClass : 'vm-info'
      partial  : "#{data.vmName}"

    @vm.fetchVMDomains data.vmName, (err, domains) =>
      if not err and domains.length > 0
        @vmInfo.updatePartial domains.first

    @terminalButton = new KDButtonView
      cssClass      : 'terminal'
      callback      : =>
        data        = @getData()
        data.treeController.emit 'TerminalRequested', data.vm

  showLoader:->

    @parent?.isLoading = yes
    @loader.show()

  hideLoader:->

    @parent?.isLoading = no
    @loader.hide()

  createSelectOptions: ->
    currentPath = @getData().path
    nickname    = KD.nick()
    parents     = []
    nodes       = currentPath.split '/'

    for x in [ 0...nodes.length ]
      nodes = currentPath.split '/'
      path  = nodes.splice(1,x).join '/'
      parents.push "/#{path}"

    parents.reverse()

    items  = []

    for path in parents when path
      items.push title: path, value: path

    return items

  checkVMState:(err, vm, info)->
    return unless vm is @getData().vmName

    if err or not info
      @unsetClass 'online'
      return warn err

    if info.state is "RUNNING"
    then @setClass 'online'
    else @unsetClass 'online'

  viewAppended:->
    super
    @getData().getKite()?.vmInfo().nodeify @bound 'checkVMState'

  pistachio:->
    """
      <div class="vm-header">
        {{> @vmInfo}}
        <div class="buttons">
          {{> @terminalButton}}
          <span class='chevron'></span>
        </div>
      </div>
      {{> @folderSelector}}
    """
