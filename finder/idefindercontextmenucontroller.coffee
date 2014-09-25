class IDE.FinderContextMenuController extends NFinderContextMenuController

  getFolderMenu: (fileView) ->

    fileData = fileView.getData()

    items =
      Expand                      :
        action                    : "expand"
        separator                 : yes
      Collapse                    :
        action                    : "collapse"
        separator                 : yes
      'Make this the top folder'  :
        action                    : 'makeTopFolder'
      'Workspace from here'       :
        action                    : 'createWorkspace'
      'Terminal from here'        :
        action                    : 'createTerminal'
        separator                 : yes
      Delete                      :
        action                    : 'delete'
        separator                 : yes
      Rename                      :
        action                    : 'rename'
      Duplicate                   :
        action                    : 'duplicate'
      Compress                    :
        children                  :
          'as .zip'               :
            action                : 'zip'
          'as .tar.gz'            :
            action                : 'tarball'
      'Set permissions'           :
        separator                 : yes
        children                  :
          customView              : new NSetPermissionsView {}, fileData
      'New file'                  :
        action                    : 'createFile'
      'New folder'                :
        action                    : 'createFolder'
      Refresh                     :
        action                    : 'refresh'

    if fileView.expanded
      delete items.Expand
    else
      delete items.Collapse

    return items
