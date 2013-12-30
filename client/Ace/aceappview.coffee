class AceAppView extends JView


  constructor: (options = {}, data) ->

    super options, data

    @aceViews            = {}
    @timestamp           = Date.now()
    @appManager          = KD.getSingleton "appManager"
    @tabHandleContainer  = new ApplicationTabHandleHolder delegate: @
    @tabView             = new AceApplicationTabView
      delegate           : this
      tabHandleContainer : @tabHandleContainer
      closeAppWhenAllTabsClosed : no
      saveSession        : yes
      sessionName        : "AceTabHistory"
    @finderWrapper       = new KDCustomHTMLView
      tagName            : 'aside'

    @attachEvents()
    @attachAppMenuEvents()


  embedFinder:->

    @appManager.open 'Finder', (finderApp)=>
      @finderController = finderApp.create()
      @finderWrapper.addSubView @finderController.getView()
      @finderController.reset()
      @finderController.on 'FileNeedsToBeOpened', (file)=>
        @openFile file, yes


  attachEvents:->

    @on "SessionDataCreated", (@sessionData) =>

    @on "UpdateSessionData", (openPanes, data) =>
      @sessionData = @createSessionData openPanes, data
      @tabView.emit "SaveSessionData", @sessionData

    @on "SessionItemClicked", (items) =>
      if items.length > 1
        @appManager.open "Ace", { forceNew: true }, (appController) =>
          appView = appController.getView()
          appView.openFile FSHelper.createFileFromPath file for file in items
      else
        @openFile FSHelper.createFileFromPath file for file in items

    @tabView.on "PaneDidShow", (pane) ->
      {aceView} = pane.getOptions()
      return  unless aceView
      {ace}     = aceView
      return  unless ace

      ace.focus()
      ace.on "ace.ready", -> ace.focus()
      ace.on "AceDidSaveAs", (name, parentPath) ->
        pane.tabHandle.setTitle title

      title = FSHelper.minimizePath(ace.data.path).replace /^localfile:\//, ''
      pane.tabHandle.setTitle title

      # if KD.getSingleton("finderController").vms.length > 1
      #   vm    = FSHelper.getVMNameFromPath ace.data.path
      #   title = "#{title} on #{vm}"  if vm

      # TODO: fatihacet - should add tab handle tooltips here

      # unless pane.tabHandle.tooltipCreated
      #   {nickname} = KD.whoami().profile
      #   title      = ace.data.path.replace("/Users/#{nickname}/", "~/").replace "localfile:/", ""
      #   pane.tabHandle.setTooltip
      #     title     : title
      #     placement : "bottom"
      #     delayIn   : 800
      #   pane.tabHandle.tooltipCreated = yes

      # ace.on "AceDidSaveAs", (name, parentPath) =>
      #   update tooltip title here

    @on "KDObjectWillBeDestroyed", ->
      KD.getSingleton("mainView").disableFullscreen()


  createSessionData: (openPanes, data = {}) ->
    paths     = []
    recordKey = "#{@id}-#{@timestamp}"

    for pane in openPanes
      {aceView} = pane.getOptions()
      continue  unless aceView
      {path} = aceView.getData()
      paths.push path if path.indexOf("localfile") is -1

    data[recordKey] = paths

    latest = data.latestSessions or= []
    latest.push recordKey if latest.indexOf(recordKey) is -1
    if latest.length > 10
      shifted = latest.shift()
      delete data[shifted]

    return @sessionData = data

  createSessionListItems: ->
    items       = {}
    sessionData = @sessionData
    {nickname}  = KD.whoami().profile
    itemCount   = 0
    for sessionId in sessionData.latestSessions?
      return items if itemCount > 14
      sessionItems = sessionData[sessionId]
      sessionItems.forEach (path, i) =>
        filePath = path.replace("/home/#{nickname}", "~")
        filePath = filePath.replace /^\[[^\[\]]*]/, ''
        items[filePath] = callback: => @emit "SessionItemClicked", [path]
        itemCount++

    return items

  preview: ->
    {path, vmName} = @getActiveAceView().getData()
    KD.singleton("appManager").create "Viewer", {path, vmName}, (app) =>
      @tabView.addPane new KDTabPaneView
        name    : "[#{path.split("/").last}]"
        view    : app.getView()

  reopenLastSession: ->
    data   = @sessionData
    latest = data.latestSessions
    if latest?.length > 0
      @emit "SessionItemClicked", data[latest.first]
    else
      @getActiveAceView().ace.notify "No recent file.", "error"

  viewAppended:->
    super
    @utils.wait 100, =>
      @embedFinder()
      @addNewTab() if @tabView.panes.length is 0

  addNewTab: (file) ->
    file = file or FSHelper.createFileFromPath 'localfile:/Untitled.txt'
    aceView = new AceView delegate: this, file
    aceView.on 'KDObjectWillBeDestroyed', => @removeOpenDocument aceView
    @aceViews[file.path] = aceView
    @setViewListeners aceView

    pane = new KDTabPaneView
      name    : file.name or 'Untitled.txt'
      aceView : aceView

    @tabView.addPane pane
    pane.addSubView aceView

  setViewListeners: (view) ->
    @setFileListeners view.getData()

  getActiveAceView: ->
    return @tabView.getActivePane().getOptions().aceView

  isFileOpen: (file) -> @aceViews[file.path]?

  openFile: (file, isAceAppOpen) ->
    if file and @isFileOpen file
      mainTabView = KD.getSingleton("mainView").mainTabView
      mainTabView.showPane @parent
      @tabView.showPane @aceViews[file.path].parent
    else
      @addNewTab file

  removeOpenDocument: (aceView) ->
    return unless aceView
    @clearFileRecords aceView

  setFileListeners: (file) ->
    view = @aceViews[file.path]
    file.on "fs.saveAs.finished", (newFile, oldFile)=>
      if @aceViews[oldFile.path]
        view = @aceViews[oldFile.path]
        @clearFileRecords view
        @aceViews[newFile.path] = view
        view.setData newFile
        view.parent.setTitle newFile.name
        view.ace.setData newFile
        @setFileListeners newFile
        view.ace.notify "New file is created!", "success"
        KD.getSingleton('mainController').emit "NewFileIsCreated", newFile
    file.on "fs.delete.finished", => @removeOpenDocument @aceViews[file.path]

  clearFileRecords: (view) ->
    file = view.getData()
    delete @aceViews[file.path]

  attachAppMenuEvents: ->
    @on "saveMenuItemClicked", => @getActiveAceView().ace.requestSave()

    @on "saveAsMenuItemClicked", => @getActiveAceView().ace.requestSaveAs()

    @on "compileAndRunMenuItemClicked", => @getActiveAceView().compileAndRun()

    @on "previewMenuItemClicked", => @preview()

    @on "reopenMenuItemClicked", => @reopenLastSession()

    @on "findMenuItemClicked", => @getActiveAceView().ace.showFindReplaceView()

    @on "findAndReplaceMenuItemClicked", => @getActiveAceView().ace.showFindReplaceView yes

    @on "gotoLineMenuItemClicked", => @getActiveAceView().ace.showGotoLine()

    @on "exitMenuItemClicked", => @appManager.quit @appManager.frontApp

  getAdvancedSettingsMenuView: ->
    pane = @tabView.getActivePane()
    {aceView} = pane.getOptions()
    settingsView = new KDView
      cssClass: "editor-advanced-settings-menu"
    settingsView.addSubView new AceSettingsView
      delegate: aceView.ace

    return settingsView

  getRecentsMenuView: ->
    items = @createSessionListItems()
    unless Object.keys(items).length
      return new KDView
        partial: "<cite>No recently opened file exists.</cite>"
    return items

  getFullscreenMenuView: (item, menu)->
    labels = [
      "Enter Fullscreen"
      "Exit Fullscreen"
    ]
    mainView = KD.getSingleton "mainView"
    state    = mainView.isFullscreen() or 0
    toggleFullscreen = new KDView
      partial : "<span>#{labels[Number state]}</span>"
      click   : =>
        @getActiveAceView().toggleFullscreen()
        menu.contextMenu.destroy()
        menu.click()
    # behave like a menu item
    toggleFullscreen.on "viewAppended", ->
      toggleFullscreen.parent.setClass "default"

  pistachio: ->
    """
      {{> @finderWrapper}}
      <section>
      {{> @tabHandleContainer}}
      {{> @tabView}}
      </section>
    """
