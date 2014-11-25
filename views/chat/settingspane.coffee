class IDE.ChatSettingsPane extends KDTabPaneView

  JView.mixin @constructor

  constructor: (options = {}, data)->

    options.cssClass = 'chat-settings'

    super options, data

    @rtm = options.rtm

    @createElements()

    @on 'CollaborationNotInitialized', => @everyone.destroySubViews()
    @on 'ParticipantJoined', @bound 'addParticipant'
    @on 'ParticipantLeft',   @bound 'removeParticipant'

    @on 'CollaborationEnded', =>
      @toggleButtons 'ended'
      @everyone.destroySubViews()

    @on 'CollaborationStarted', =>
      @toggleButtons 'started'
      @createParticipantsList()


  createElements: ->

    channel = @getData()

    @title = new KDCustomHTMLView
      tagName  : 'h3'
      cssClass : 'workspace-name'
      partial  : 'My Workspace'

    @chevron = new KDCustomHTMLView
      tagName  : 'figure'
      cssClass : 'pm-title-chevron'

    @link = new KDCustomHTMLView
      tagName    : 'a'
      cssClass   : 'session-link'
      partial    : link = KD.utils.groupifyLink "IDE/#{channel.id}", yes
      attributes : href : link
      # click      : (event) ->
      #   KD.utils.stopDOMEvent event
      #   # errs saying 'Discontiguous selection is not supported.' needs research - SY
      #   KD.utils.selectText @getElement()

    @startSession = new KDButtonView
      title    : 'START SESSION'
      cssClass : 'solid green'
      callback : @bound 'initiateSession'

    @endSession = new KDButtonView
      title    : 'END SESSION'
      disabled : yes
      cssClass : 'solid red hidden'
      callback : @bound 'stopSession'

    @back = new KDButtonView
      title    : 'back to chat'
      cssClass : 'solid green mini'
      callback : => @getDelegate().showChatPane()

    @defaultSetting = new KDSelectBox
      defaultValue  : 'edit'
      selectOptions : [
        { title : 'CAN READ', value : 'read'}
        { title : 'CAN EDIT', value : 'edit'}
      ]

    @myself    = new IDE.ChatParticipantView
      isOnline : yes
      isMe     : yes
      cssClass : 'myself'
    , KD.whoami()

    @everyone  = new KDCustomHTMLView
      tagName  : 'ul'
      cssClass : 'settings everyone loading'

    @everyone.addSubView new KDLoaderView
      showLoader : yes
      size       :
        width    : 24

    @everyone.addSubView new KDCustomHTMLView
      cssClass : 'label'
      partial  : 'Fetching participants'


  initiateSession: ->

    @startSession.disable()
    {appManager} = KD.singletons

    appManager.tell 'IDE', 'startCollaborationSession', (err, channel) =>

      return @startSession.enable()  if err

      @toggleButtons 'started'


  stopSession: ->

    @endSession.disable()
    {appManager} = KD.singletons

    appManager.tell 'IDE', 'stopCollaborationSession', (err, channel) =>

      return @endSession.enable()  if err

      @toggleButtons 'ended'


  toggleButtons: (state) ->
    startButton = @startSession
    endButton   = @endSession

    if state is 'started'
      endButton.show()
      endButton.enable()
      startButton.hide()
      startButton.disable()
    else
      startButton.show()
      startButton.enable()
      endButton.hide()
      endButton.disable()


  createParticipantsList: ->

    @everyone.unsetClass 'loading'
    @everyone.destroySubViews()

    nickname          = KD.nick()
    participants      = @rtm.getFromModel('participants').asArray()
    @participantViews = {}

    for participant in participants when participant.nickname isnt nickname
      @createParticipantView participant


  createParticipantView: (data) =>

    view = new IDE.ChatParticipantView {}, data
    @participantViews[data.nickname] = view
    @everyone.addSubView view


  removeParticipant: (username) ->

    @participantViews[username]?.destroy()
    delete @participantViews[username]


  addParticipant: (nickname) ->

    return  if @participantViews[nickname]

    # KD.getSingleton('appManager').tell 'IDE', 'addParticipant', nickname, =>

    #   @createParticipantView { nickname }


  viewAppended: JView::viewAppended

  setTemplate: JView::setTemplate


  pistachio: ->

    """
    <header>
    {{> @title}}{{> @chevron}}
    {{> @link}}
    <div class='buttons'>
      {{> @startSession}} {{> @endSession}}
    </div>
    </header>
    <ul class='settings default'>
      <li><label>Anyone who joins</label>{{> @defaultSetting}}</li>
    </ul>
    {{> @myself}}
    {{> @everyone}}
    {{> @back}}
    """
