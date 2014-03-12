class FSHelper

  parseWatcherFile = (vm, parentPath, file, user, treeController)->

    {name, size, mode} = file
    type      = if file.isBroken then 'brokenLink' else \
                if file.isDir then 'folder' else 'file'
    path      = if parentPath is "[#{vm}]/" then "[#{vm}]/#{name}" else \
                "#{parentPath}/#{name}"
    group     = user
    createdAt = file.time
    return { size, user, group, createdAt, mode, type, \
             parentPath, path, name, vmName:vm, treeController }

  @parseWatcher = (vm, parentPath, files, treeController)->

    data = []
    return data unless files
    files = [files] unless Array.isArray files

    sortedFiles = []
    for p in [yes, no]
      z = (x for x in files when x.isDir is p).sort (x,y)->
        x.name.toLowerCase() > y.name.toLowerCase()
      sortedFiles.push x for x in z

    nickname = KD.nick()
    for file in sortedFiles
      data.push FSHelper.createFile \
        parseWatcherFile vm, parentPath, file, nickname, treeController

    return data

  @folderOnChange = (vm, path, change, treeController)->
    return  unless treeController
    file = (@parseWatcher vm, path, change.file, treeController).first
    switch change.event
      when "added"
        treeController.addNode file
      when "removed"
        for own npath, node of treeController.nodes
          if npath is file.path
            treeController.removeNodeView node
            break

  @plainPath:(path)-> path.replace /\[.*\]/, ''
  @getVMNameFromPath:(path)-> (/\[([^\]]+)\]/g.exec path)?[1]

  @minimizePath: (path)-> @plainPath(path).replace ///^\/home\/#{KD.nick()}///, '~'

  @grepInDirectory = (keyword, directory, callback, matchingLinesCount = 3) ->
    command = "grep #{keyword} '#{directory}' -n -r -i -I -H -T -C#{matchingLinesCount}"
    KD.getSingleton('vmController').run command, (err, res) =>
      result = {}

      if res
        chunks = res.split "--\n"

        for chunk in chunks
          lines = chunk.split "\n"

          for line in lines when line
            [lineNumberWithPath, line] = line.split "\t"
            [lineNumber]               = lineNumberWithPath.match /\d+$/
            path                       = lineNumberWithPath.split(lineNumber)[0].trim()
            path                       = path.substring 0, path.length - 1
            isMatchedLine              = line.charAt(1) is ":"
            line                       = line.substring 2, line.length

            result[path] = {} unless result[path]
            result[path][lineNumber] = {
              lineNumber
              line
              isMatchedLine
              path
            }

      callback? result

  @exists = (path, vmName, callback=noop)->
    @getInfo path, vmName, (err, res)->
      callback err, res?

  @getInfo = (path, vmName, callback=noop)->
    KD.getSingleton('vmController').run
      method   : "fs.getInfo"
      vmName   : vmName
      withArgs : {path}
    , callback

  @glob = (pattern, vmName, callback)->
    [vmName, callback] = [callback, vmName]  if typeof vmName is "function"
    KD.getSingleton('vmController').run
      method   : "fs.glob"
      vmName   : vmName
      withArgs : {pattern}
    , callback

  @ensureNonexistentPath = (path, vmName, callback=noop)->
    KD.getSingleton('vmController').run
      method   : "fs.ensureNonexistentPath"
      vmName   : vmName
      withArgs : {path}
    , callback

  @registry = {}

  @resetRegistry:-> @registry = {}

  @register = (file)->
    @setFileListeners file
    @registry[file.path] = file

  @unregister = (path)->
    delete @registry[path]

  @unregisterVmFiles = (vmName)->
    for own path, file of @registry  when (path.indexOf "[#{vmName}]") is 0
      @unregister path

  @updateInstance = (fileData)->
    for own prop, value of fileData
      @registry[fileData.path][prop] = value

  @setFileListeners = (file)->
    file.on "fs.job.finished", =>

  @getFileNameFromPath = getFileName = (path)->
    return path.split('/').pop()

  @trimExtension = (path)->
    name = getFileName path
    return name.split('.').shift()

  @getParentPath = (path)->
    path = path.substr(0, path.length-1) if path.substr(-1) is "/"
    parentPath = path.split('/')
    parentPath.pop()
    return parentPath.join('/')

  @createFileFromPath = (path, type = "file")->
    return warn "pass a path to create a file instance" unless path
    vmName     = @getVMNameFromPath(path) or null
    path       = @plainPath path  if vmName
    parentPath = @getParentPath path
    name       = @getFileNameFromPath path
    return @createFile { path, parentPath, name, type, vmName }

  @createFile = (options)->
    unless options and options.type and options.path
      return warn "pass a path and type to create a file instance"

    unless options.vmName?
      options.vmName = KD.getSingleton('vmController').defaultVmName

    if @registry[options.path]
      instance = @registry[options.path]
      @updateInstance options
    else
      constructor = switch options.type
        when "vm"         then FSVm
        when "folder"     then FSFolder
        when "mount"      then FSMount
        when "symLink"    then FSFolder
        when "brokenLink" then FSBrokenLink
        else FSFile

      instance = new constructor options
      @register instance

    return instance

  @createRecursiveFolder = ({ path, vmName }, callback = noop) ->
    return warn "Pass a path to create folders recursively"  unless path

    KD.getSingleton("vmController").run {
      method      : "fs.createDirectory"
      withArgs    : {
        recursive : yes
        path
      }
      vmName
    }, callback

  @isValidFileName = (name) ->
    return /^([a-zA-Z]:\\)?[^\x00-\x1F"<>\|:\*\?/]+$/.test name

  @isEscapedPath = (path) ->
    return /^\s\"/.test path

  @escapeFilePath = (name) ->
    return FSHelper.plainPath name.replace(/\'/g, '\\\'').replace(/\"/g, '\\"').replace(/\ /g, '\\ ')

  @unescapeFilePath = (name) ->
    return name.replace(/^(\s\")/g,'').replace(/(\"\s)$/g, '').replace(/\\\'/g,"'").replace(/\\"/g,'"')

  @isPublicPath = (path)->
    /^\/home\/.*\/Web\//.test FSHelper.plainPath path

  @convertToRelative = (path)->
    path.replace(/^\//, "").replace /(.+?)\/?$/, "$1/"

  @isUnwanted = (path, isFile=no)->

    dummyFilePatterns = /\.DS_Store|Thumbs.db/
    dummyFolderPatterns = /\.git|__MACOSX/
    if isFile
    then dummyFilePatterns.test path
    else dummyFolderPatterns.test path

  @s3 =
    get    : (name)->
      "#{KD.config.uploadsUri}/#{KD.whoami().getId()}/#{name}"

    getGroupRelated : (group, name)->
      "#{KD.config.uploadsUriForGroup}/#{group}/#{name}"

    upload : (name, content, bucket, path, callback)->
      args = {name, bucket, path, content}

      KD.getSingleton('vmController').run
        method    : 's3.store'
        withArgs  : args
      , (err, res)->
        return callback err if err
        filePath = if bucket is "groups" then FSHelper.s3.getGroupRelated path, name else FSHelper.s3.get name
        callback null, filePath

    remove : (name, callback)->
      vmController = KD.getSingleton 'vmController'
      vmController.run
        method    : 's3.delete'
        withArgs  : {name}
      , callback

  @getPathHierarchy = (fullPath)->
    {path, vmName} = KD.getPathInfo fullPath
    path = path.replace /^~/, "/home/#{KD.nick()}"
    nodes = path.split("/").filter (node)-> return !!node
    queue = for node in nodes
      subPath = nodes.join "/"
      nodes.pop()
      "[#{vmName}]/#{subPath}"
    queue.reverse() # reverse the queue to open files to back

  @chunkify = (data, chunkSize)->
    chunks = []
    while data
      if data.length < chunkSize
        chunks.push data
        break
      else
        chunks.push data.substr 0, chunkSize
        # shrink
        data = data.substr chunkSize
    return chunks

  @getFullPath = (file)->
    plainPath = @plainPath file.path
    return "[#{file.vmName}]#{plainPath}"

KD.classes.FSHelper = FSHelper
