require "git_keyvalue/version"

module GitKeyvalue
  # known good with ruby 1.9.3, with git 1.7.9.6

  require 'pathname'
  require 'tmpdir'
  require 'fileutils'

  class KeyValueGitError < StandardError
  end

  ##
  # Provides a GET/PUT-style interface for a git repo. In effect, it
  # presents the repo as a key/value store, where the keys are file
  # paths (relative to the repo's root) and the values are the contents
  # of those files.
  #
  # == Requirements
  # Known good with ruby 1.9.3 and git 1.7.9.6.
  # 
  # == Performance & resource usage
  #
  # Not performant. Must clone the repo before performing any
  # operations. Needs whatever disk space is required for a repo clone.
  # Clears this space when the object is destroyed.
  #
  # == Object lifetime
  #
  # Stores the local repo in the OS's temporary directory. Therefore,
  # you should not expect this object to remain valid across automated
  # housekeeping events that might destroy this directory.
  #
  # == Footnote on shallow cloning
  # 
  # Okay, technically, this does not clone the entire repo. For better
  # performance it does a "shallow clone" of the repo, which grabs only
  # the files necessary to represent the HEAD commit. Such a shallow
  # clone is officially enough to enable GET operations, which read only
  # those files anyway. However, according to the git-clone docs, the
  # shallow clone is _not_ officially enough to enable git-push to
  # update those files on the remote repo. However, this seems like a
  # bug in the git-clone docs since, in reality, a shallow clone is
  # enough and should be enough for pushing new commits, since a new
  # commit only needs to reference its parent commit(s).
  #
  # The bottom line: by using shallow cloning for better perf, this
  # class is relying on undocumented behavior in git-push. This works
  # fine as of git version 1.7.9.6. I see no reason to expect this to
  # break in the future, since this undocumented behavior follows
  # directly from git's data model, which is stable. However, if it does
  # break, and you want to switch to using the documented git behavior,
  # then set USE_SHALLOW_CLONING to false.
  #
  class KeyValueRepo
    private
    # whether to git-clone only the HEAD commit of the remote repo
    USE_SHALLOW_CLONING = true

    # @return [Proc] proc which removes the temporary local clone of the repo
    def self.make_finalizer(tmp_dir)
      proc do
        puts 'KeyValueRepo: Remove local repo clone in ' + tmp_dir
        FileUtils.remove_entry_secure(tmp_dir)
      end
    end

    ##
    # Updates the local clone of the repo
    # @raise [KeyValueGitError] if cannot pull the repo.
    def update_local_repo
      Dir.chdir(@path_to_repo) do
        success = system('git','pull')
        if not success
          raise KeyValueGitError, 'Failed to pull updated version of the repo, even though it was cloned successfully. Aborting.'
        end
      end
    end

    ##
    # Checks if path_in_repo points to a file existing in the repo.
    #
    # @param [String] path_in_repo
    # @return [Boolean] whether 
    #
    # Even if path_in_repo starts with /, it will be interpreted as
    # relative to the repo's root.
    def isFileExistingWithinRepo(path_in_repo)
      abspath = Pathname.new(File.join(@path_to_repo,path_in_repo))
      # see if the file exists and is a file
      if abspath.file?
        # and if it's within the repo
        abspath.realpath.to_s.start_with?(Pathname.new(@path_to_repo).realpath.to_s)
      else
        false
      end
    end

    ##
    # Strips any initial / chars from +maybe_abspath+
    #
    # @param [String] maybe_abspath
    # @return [String]
    #
    def blindly_relativize_path(maybe_abspath)
      (maybe_abspath.split('').drop_while {|ch| ch=='/'}).join
    end

    ##
    # Ensure a file exists and execute a GET-like operation, passed as a block.
    #
    # @param path_in_repo [String] relative path of a repo file
    # @yieldparam abspath [String] absolute filesystem path for the block to GET
    # @yieldreturn [Object,nil] result of GETting the file, or nil if the block returned its value through side-effects 
    # @return [Object,nil] the result returned by the block, or nil if the file does not exist
    # @raise [KeyValueGitError] if cannot pull from the repo
    # @raise [Exception] if the block raises an Exception
    # 
    # Updates the local repo. Verifies the file exists at
    # path_in_repo. If it does not exist or is outside of the repo,
    # returns nil. Otherwise, returns the result of calling the block.
    #
    # This method will raise whatever the block raises
    def outer_get(path_in_repo)
      update_local_repo
      if not isFileExistingWithinRepo(path_in_repo)
        nil
      else
        abspath = Pathname.new(File.join(@path_to_repo,path_in_repo)).realpath.to_s
        yield abspath
      end
    end

    ##
    # Prepares and executes a PUT-like operation, passed as a block
    #
    # @param path_in_repo [String] relative path of repo file
    # @yield
    # @return the result returned by the block
    #
    # @raise [KeyValueGitError] if can't pull or push the repo
    # @raise [Exception] if the block raises an Exception
    #
    # Update the local repo, changes to its root directory, then calls
    # the block to execute the PUT operation on the repo's working
    # tree. Then commits and push that change to the remote repo.
    def outer_put(path_in_repo)
      update_local_repo
      Dir.chdir(@path_to_repo) do

        yield

        # add and commit to repo
        system('git','add',path_in_repo)
        system('git','commit','-m','\'git-keyvalue: updating ' + path_in_repo + '\'')
        success = system('git','push')
        if not success
          # restore local repo to a good state
          system('git','clean','--force','-d')
          # report the failure
          raise KeyValueGitError, 'Failed to push commit with updated file. This could be because someone else pushed to the repository in the middle of this operation. If this is the problem, you should be able simply to re-try this operation. If the problem is deeper, you might create a fresh object before re-trying.'
        end
      end
    end

    public

    # @return [String] URL of the remote git repo
    attr_reader :repo_url
    # @return [String] absolute filesystem path of the local repo
    attr_reader :path_to_repo

    ##
    # Clones the remote repo, failing if it is invalid or inaccessible.
    # 
    # @param repo_url [String] URL of a valid, network-accessible, permissions-accessible git repo
    #
    # As it clones the entire repo, this may take a long time if you are
    # manipulating a large remote repo. Keeps the repo in the OS's
    # temporary directory, so you should not expect this object to
    # remain valid across automated cleanups of that temporary directory
    # (which happen, for instance, typically at restart).
    # 
    # @raise [KeyValueGitError] if unable to clone the repo
    def initialize(repo_url)
      @repo_url = repo_url
      @path_to_repo = Dir.mktmpdir('KeyValueGitTempDir')
      if USE_SHALLOW_CLONING
        # experimental variant. uses undocumented behaviour of
        # git-clone. This is because setting --depth 1 produces a
        # shallow clone, which according to the docs does not let you
        # git-push aftewards, but in reality should and does let you
        # git-push. This is a bug in the git documentation.
        success = system('git','clone','--depth','1',@repo_url,@path_to_repo)  
      else
        # stable variant. uses documented behavior of git-clone
        success = system('git','clone',@repo_url,@path_to_repo) 
      end
      if not success
        raise KeyValueGitError, 'Failed to initialize, because could not clone the remote repo: ' + repo_url + '. Please verify this is a valid git URL, and that any required network connection or login credentials are available.'
      end
      ObjectSpace.define_finalizer(self, self.class.make_finalizer(@path_to_repo))
    end

    ##
    # Get contents of a file, or nil if it does not exist
    #
    # @param path_in_repo [String] relative path of repo file to get
    # @return [String,nil] string contents of file, or nil if non-existent
    #
    def get(path_in_repo)
      outer_get(path_in_repo) { |abspath| File.read(abspath) }
    end

    ##
    # Copies the repo file at +path_in_repo+ to +dest_path+
    #
    # @param path_in_repo [String] relative path of repo file to get
    # @param dest_path [String] path to which to copy the gotten file
    #
    # Does no validation regarding dest_path. If dest_path points to a
    # file, it will overwrite that file. If it points to a directory, it
    # will copy into that directory.
    def getfile(path_in_repo, dest_path)
      outer_get(path_in_repo) { |abspath| FileUtils.cp(abspath, dest_path) }
    end

    ##
    # Sets the contents of the file at +path_in_repo+, creating it if necessary
    #
    # @param path_in_repo [String] relative path of repo file to add or update
    # @param string_value [String] the new contents for the file at this path
    #
    def put(path_in_repo, string_value)
      path_in_repo = blindly_relativize_path(path_in_repo)
      outer_put(path_in_repo) {
        # create parent directories if needed
        FileUtils.mkdir_p(File.dirname(path_in_repo))
        # write new file contents
        File.open(path_in_repo,'w') { |f| f.write(string_value) }
      }    
    end

    ##
    # Sets the contents of the file at path, creating it if necessary
    #
    # @param path_in_repo [String] relative path of repo file to add or update
    # @param src_file_path [String] file to use for replacing +path_in_repo+
    #
    def putfile(path_in_repo, src_file_path)
      path_in_repo = blindly_relativize_path(path_in_repo)
      outer_put(path_in_repo) {
        # create parent directories if needed
        FileUtils.mkdir_p(File.dirname(path_in_repo))
        # copy file at src_file_path into the path_in_repo
        abspath = Pathname.new(File.join(@path_to_repo,path_in_repo)).to_s
        FileUtils.cp(src_file_path, abspath)
      }
    end
  end
end
