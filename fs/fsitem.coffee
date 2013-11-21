class FSItem extends KDObject

  ###
  CLASS CONTEXT
  ###

  escapeFilePath = FSHelper.escapeFilePath

  @create:(path, type, vmName, callback)->

    FSHelper.ensureNonexistentPath path, vmName, (err, response)->
      if err
        callback? err, response
        warn err
      else
        KD.getSingleton('vmController').run
          method           : if type is 'folder' then "fs.createDirectory" \
                             else "fs.writeFile"
          vmName           : vmName
          withArgs         :
            path           : FSHelper.plainPath response
            content        : ""
            donotoverwrite : yes
        , (err, res)->
          if err then warn err
          else
            file = FSHelper.createFile {path:response, type, vmName}
          callback? err, file

  @copy:(sourceItem, targetItem, callback)->

    sourceItem.emit "fs.job.started"
    targetPath = FSHelper.plainPath "#{targetItem.path}/#{sourceItem.name}"
    vmName = targetItem.vmName or FSHelper.getVMNameFromPath targetPath
    FSHelper.ensureNonexistentPath targetPath, vmName, (err, response)->
      if err
        warn err
        callback? err, response
      else
        KD.getSingleton('vmController').run
          vmName   : vmName
          withArgs : "cp -R #{escapeFilePath(sourceItem.path)} #{escapeFilePath(response)}"
        , (err, res)->
          sourceItem.emit "fs.job.finished"
          if err then warn err
          else
            file = FSHelper.createFileFromPath "#{targetItem.path}/#{sourceItem.name}", sourceItem.type
          callback? err, file

  @move:(sourceItem, targetItem, callback)->

    sourceItem.emit "fs.job.started"
    targetPath = FSHelper.plainPath "#{targetItem.path}/#{sourceItem.name}"
    vmName = targetItem.vmName or FSHelper.getVMNameFromPath targetPath
    FSHelper.ensureNonexistentPath targetPath, vmName, (err, response)->
      if err
        warn err
        callback? err, response
      else
        KD.getSingleton('vmController').run
          vmName   : vmName
          withArgs : "mv #{escapeFilePath(sourceItem.path)} #{escapeFilePath(response)}"
        , (err, res)->
          sourceItem.emit "fs.job.finished"
          if err then warn err
          else
            file = FSHelper.createFileFromPath targetPath, sourceItem.type
          callback? err, file

  @compress:(file, type, callback)->

    file.emit "fs.job.started"
    path = FSHelper.plainPath "#{file.path}.#{type}"
    vmName = file.vmName or FSHelper.getVMNameFromPath path
    FSHelper.ensureNonexistentPath path, vmName, (err, response)->
      if err
        warn err
        callback? err, response
      else
        command = switch type
          when "tar.gz" then "tar -pczf #{escapeFilePath response} #{escapeFilePath file.path}"
          else "zip -r #{escapeFilePath response} #{escapeFilePath file.path}"
        KD.getSingleton('vmController').run
          vmName   : vmName
          withArgs : command
        , (err, res)->
          file.emit "fs.job.finished"
          if err then warn err
          callback? err, res

  @extract:(file, callback)->

    tarPattern = /\.tar\.gz$/
    zipPattern = /\.zip$/

    file.emit "fs.job.started"
    path = FSHelper.plainPath file.path
    vmName = file.vmName or FSHelper.getVMNameFromPath path
    command = if tarPattern.test file.name
      extractFolder = file.path.replace tarPattern, ''
      "cd #{escapeFilePath file.parentPath};mkdir -p #{escapeFilePath extractFolder};tar -zxf #{escapeFilePath file.name} -C #{escapeFilePath extractFolder}"
    else if zipPattern.test file.name
      extractFolder = file.path.replace zipPattern, ''
      "cd #{escapeFilePath file.parentPath};unzip -o #{escapeFilePath file.name} -d #{escapeFilePath extractFolder}"

    if command
      KD.getSingleton('vmController').run
        vmName   : vmName
        withArgs : command
      , (err, res)->
        file.emit "fs.job.finished"
        if err then warn err
        folder = FSHelper.createFileFromPath extractFolder, 'folder'
        callback? err, folder
    else callback? yes

  @getFileExtension: (path) ->
    fileName = path or ''
    [name, extension...]  = fileName.split '.'
    extension = if extension.length is 0 then '' else extension.last

  @getFileType: (extension)->

    fileType = null

    _extension_sets =
      code    : [
        "php", "pl", "py", "jsp", "asp", "htm","html", "phtml","shtml"
        "sh", "cgi", "htaccess","fcgi","wsgi","mvc","xml","sql","rhtml"
        "js","json","coffee", "css","styl","sass", "erb"
      ]
      text    : [
        "txt", "doc", "rtf", "csv", "docx", "pdf"
      ]
      archive : [
        "zip","gz","bz2","tar","7zip","rar","gzip","bzip2","arj","cab"
        "chm","cpio","deb","dmg","hfs","iso","lzh","lzma","msi","nsis"
        "rpm","udf","wim","xar","z","jar","ace","7z","uue"
      ]
      image   : [
        "png","gif","jpg","jpeg","bmp","svg","psd","qt","qtif","qif"
        "qti","tif","tiff","aif","aiff"
      ]
      video   : [
        "avi","mp4","h264","mov","mpg","ra","ram","mpg","mpeg","m4a"
        "3gp","wmv","flv","swf","wma","rm","rpm","rv","webm"
      ]
      sound   : ["aac","au","gsm","mid","midi","snd","wav","3g2","mp3","asx","asf"]
      app     : ["kdapp"]


    for own type,set of _extension_sets
      for ext in set when extension is ext
        fileType = type
        break
      break if fileType

    return fileType or 'unknown'

  @isHidden: (name)-> return /^\./.test name

  ###
  INSTANCE METHODS
  ###

  constructor:(options, data)->

    @[key] = value for own key, value of options

    super

    @vmController   = KD.getSingleton('vmController')

  getExtension:-> FSItem.getFileExtension @name

  isHidden:-> FSItem.isHidden @name

  exists:(callback=noop)->
    FSHelper.exists @path, @vmName, callback

  stat:(callback=noop)->
    FSHelper.getInfo @path, @vmName, callback

  remove:(callback, recursive=no)->
    @emit "fs.delete.started"
    KD.getSingleton('vmController').run
      method      : "fs.remove"
      vmName      : @vmName
      withArgs    :
        path      : FSHelper.plainPath @path
        recursive : recursive
    , (err, response)=>
      callback err, response
      if err then warn err
      else
        @emit "fs.delete.finished"
        @destroy()

  rename:(newName, callback)->

    newPath = FSHelper.plainPath "#{@parentPath}/#{newName}"

    @emit "fs.job.started"
    FSHelper.ensureNonexistentPath newPath, @vmName, (err, response)=>
      if err
        warn err
        callback? err, response
      else
        KD.getSingleton('vmController').run
          method    : "fs.rename"
          vmName    : @vmName
          withArgs  :
            oldpath : FSHelper.plainPath @path
            newpath : newPath
        , (err, res)=>
          if err then warn err
          else
            @path = newPath
            @name = newName
          callback? err, @
          @emit "fs.job.finished"

  chmod:(options, callback)->

    {recursive, permissions} = options

    return callback? "no permissions passed" unless permissions?
    @emit "fs.job.started"

    KD.getSingleton('vmController').run
      method      : "fs.setPermissions"
      vmName      : @vmName
      withArgs    :
        path      : FSHelper.plainPath @path
        recursive : recursive
        mode      : permissions
    , (err, res)=>
      @emit "fs.job.finished"
      if err then warn err
      else
        @mode = permissions
      callback? err,res
