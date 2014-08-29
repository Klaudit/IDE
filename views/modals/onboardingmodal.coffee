class IDE.OnboardingModal extends IDE.ModalView

  constructor: (options = {}, data) ->

    options.cssClass = KD.utils.curry 'ide-onboarding-modal', options.cssClass
    options.width    = 590
    options.height   = 430

    super options, data

    @content = new IDE.OnboardingModalContent
    @content.on 'GetStartedButtonClicked', @bound 'handleGetStarted'

    @addSubView @content

    @show()


  handleGetStarted: ->

    { appStorageController } = KD.singletons

    appStorage = appStorageController.storage 'IDE', '1.0.0'
    appStorage.setValue 'hideOnboardingModal', yes

    @destroy()

    @emit 'OnboardingModalDismissed'


