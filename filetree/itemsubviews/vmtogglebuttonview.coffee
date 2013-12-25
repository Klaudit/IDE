class NVMToggleButtonView extends JView

  constructor:(options, data)->
    super cssClass: 'vm-toggle-menu', data

    @vm = KD.getSingleton 'vmController'
    @vm.on 'StateChanged', @bound 'checkVMState'

    @toggle = new KDOnOffSwitch
      cssClass : "tiny vm-toggle-item"
      callback : (state)=>
        if state
        then @vm.start @getData().vmName
        else @vm.stop  @getData().vmName

  checkVMState:(err, vm, info)->
    return unless vm is @getData().vmName

    if err or not info

      @notification?.destroy()
      @notification = new KDNotificationView
        type    : "mini"
        cssClass: "error"
        duration: 5000
        title   : "I cannot turn this machine on, please give it a few seconds."

      @toggle.setDefaultValue no
      # KD.utils.notifyAndEmailVMTurnOnFailureToSysAdmin vm, err.message
      KD.logToExternal "oskite: vm failed to turn on since #{err.message}", {vm}
      return warn err

    if info.state is "RUNNING"
    then @toggle.setDefaultValue yes
    else @toggle.setDefaultValue no

  pistachio:->
    """<span>Change state</span> {{> @toggle}}"""

  viewAppended:->
    super
    @vm.info @getData().vmName, @bound 'checkVMState'