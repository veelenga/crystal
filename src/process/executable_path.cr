# Reference:
# - https://github.com/gpakosz/whereami/blob/master/src/whereami.c
# - http://stackoverflow.com/questions/1023306/finding-current-executables-path-without-proc-self-exe

class Process
  PATH_DELIMITER = {% if flag?(:windows) %} ';' {% else %} ':' {% end %}

  # :nodoc:
  INITIAL_PATH = ENV["PATH"]?

  # :nodoc:
  INITIAL_PWD = Dir.current

  # Returns an absolute path to the executable file of the currently running
  # program. This is in opposition to `PROGRAM_NAME` which may be a relative or
  # absolute path, just the executable file name or a symlink.
  #
  # The executable path will be canonicalized (all symlinks and relative paths
  # will be expanded).
  #
  # Returns `nil` if the file can't be found.
  def self.executable_path
    if executable = executable_path_impl
      begin
        File.real_path(executable)
      rescue File::Error
      end
    end
  end

  # Searches an executable, checking for an absolute path, a path relative to
  # *pwd* or absolute path, then eventually searching in directories declared
  # in *path*.
  def self.find_executable(name : Path | String, path : String? = ENV["PATH"]?, pwd : Path | String = Dir.current) : String?
    name = Path.new(name)
    if name.absolute?
      return name.to_s
    end

    # check if the name includes a separator
    count_parts = 0
    name.each_part do
      count_parts += 1
      break if count_parts > 1
    end

    if count_parts > 1
      return name.expand(pwd).to_s
    end

    return unless path

    path.split(PATH_DELIMITER).each do |path_entry|
      executable = Path.new(path_entry, name)
      return executable.to_s if File.exists?(executable)
    end

    nil
  end
end

{% if flag?(:darwin) %}
  lib LibC
    PATH_MAX = 1024
    fun _NSGetExecutablePath(buf : Char*, bufsize : UInt32*) : Int
  end

  class Process
    private def self.executable_path_impl
      buf = GC.malloc_atomic(LibC::PATH_MAX).as(UInt8*)
      size = LibC::PATH_MAX.to_u32

      if LibC._NSGetExecutablePath(buf, pointerof(size)) == -1
        buf = GC.malloc_atomic(size).as(UInt8*)
        return nil if LibC._NSGetExecutablePath(buf, pointerof(size)) == -1
      end

      String.new(buf)
    end
  end
{% elsif flag?(:freebsd) || flag?(:dragonfly) %}
  require "c/sysctl"

  class Process
    private def self.executable_path_impl
      mib = Int32[LibC::CTL_KERN, LibC::KERN_PROC, LibC::KERN_PROC_PATHNAME, -1]
      buf = GC.malloc_atomic(LibC::PATH_MAX).as(UInt8*)
      size = LibC::SizeT.new(LibC::PATH_MAX)

      if LibC.sysctl(mib, 4, buf, pointerof(size), nil, 0) == 0
        String.new(buf, size - 1)
      end
    end
  end
{% elsif flag?(:linux) %}
  class Process
    private def self.executable_path_impl
      "/proc/self/exe"
    end
  end
{% elsif flag?(:win32) %}
  require "crystal/system/windows"
  require "c/libloaderapi"

  class Process
    private def self.executable_path_impl
      Crystal::System.retry_wstr_buffer do |buffer, small_buf|
        len = LibC.GetModuleFileNameW(nil, buffer, buffer.size)
        if 0 < len < buffer.size
          break String.from_utf16(buffer[0, len])
        elsif small_buf && len == buffer.size
          next 32767 # big enough. 32767 is the maximum total path length of UNC path.
        else
          break nil
        end
      end
    end
  end
{% else %}
  # openbsd, ...
  class Process
    private def self.executable_path_impl
      find_executable(PROGRAM_NAME, INITIAL_PATH, INITIAL_PWD)
    end
  end
{% end %}
