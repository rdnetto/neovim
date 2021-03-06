local helpers = require('test.unit.helpers')(after_each)
local itp = helpers.gen_itp(it)
local cimported = helpers.cimport(
  './src/nvim/os/shell.h',
  './src/nvim/option_defs.h',
  './src/nvim/main.h',
  './src/nvim/misc1.h',
  './src/nvim/memory.h'
)
local ffi, eq = helpers.ffi, helpers.eq
local intern = helpers.internalize
local to_cstr = helpers.to_cstr
local NULL = ffi.cast('void *', 0)

describe('shell functions', function()
  before_each(function()
    -- os_system() can't work when the p_sh and p_shcf variables are unset
    cimported.p_sh = to_cstr('/bin/bash')
    cimported.p_shcf = to_cstr('-c')
    cimported.p_sxq = to_cstr('')
    cimported.p_sxe = to_cstr('')
  end)

  local function shell_build_argv(cmd, extra_args)
    local res = cimported.shell_build_argv(
        cmd and to_cstr(cmd),
        extra_args and to_cstr(extra_args))
    local argc = 0
    local ret = {}
    -- Explicitly free everything, so if it is not in allocated memory it will
    -- crash.
    while res[argc] ~= nil do
      ret[#ret + 1] = ffi.string(res[argc])
      cimported.xfree(res[argc])
      argc = argc + 1
    end
    cimported.xfree(res)
    return ret
  end

  local function os_system(cmd, input)
    local input_or = input and to_cstr(input) or NULL
    local input_len = (input ~= nil) and string.len(input) or 0
    local output = ffi.new('char *[1]')
    local nread = ffi.new('size_t[1]')

    local argv = ffi.cast('char**',
                          cimported.shell_build_argv(to_cstr(cmd), nil))
    local status = cimported.os_system(argv, input_or, input_len, output, nread)

    return status, intern(output[0], nread[0])
  end

  describe('os_system', function()
    itp('can echo some output (shell builtin)', function()
      local cmd, text = 'echo -n', 'some text'
      local status, output = os_system(cmd .. ' ' .. text)
      eq(text, output)
      eq(0, status)
    end)

    itp('can deal with empty output', function()
      local cmd = 'echo -n'
      local status, output = os_system(cmd)
      eq('', output)
      eq(0, status)
    end)

    itp('can pass input on stdin', function()
      local cmd, input = 'cat -', 'some text\nsome other text'
      local status, output = os_system(cmd, input)
      eq(input, output)
      eq(0, status)
    end)

    itp('returns non-zero exit code', function()
      local status = os_system('exit 2')
      eq(2, status)
    end)
  end)

  describe('shell_build_argv', function()
    itp('works with NULL arguments', function()
      eq({'/bin/bash'}, shell_build_argv(nil, nil))
    end)

    itp('works with cmd', function()
      eq({'/bin/bash', '-c', 'abc  def'}, shell_build_argv('abc  def', nil))
    end)

    itp('works with extra_args', function()
      eq({'/bin/bash', 'ghi  jkl'}, shell_build_argv(nil, 'ghi  jkl'))
    end)

    itp('works with cmd and extra_args', function()
      eq({'/bin/bash', 'ghi  jkl', '-c', 'abc  def'}, shell_build_argv('abc  def', 'ghi  jkl'))
    end)

    itp('splits and unquotes &shell and &shellcmdflag', function()
      cimported.p_sh = to_cstr('/Program" "Files/zsh -f')
      cimported.p_shcf = to_cstr('-x -o "sh word split" "-"c')
      eq({'/Program Files/zsh', '-f',
          'ghi  jkl',
          '-x', '-o', 'sh word split',
          '-c', 'abc  def'},
         shell_build_argv('abc  def', 'ghi  jkl'))
    end)

    itp('applies shellxescape (p_sxe) and shellxquote (p_sxq)', function()
      cimported.p_sxq = to_cstr('(')
      cimported.p_sxe = to_cstr('"&|<>()@^')

      local argv = ffi.cast('char**',
                        cimported.shell_build_argv(to_cstr('echo &|<>()@^'), nil))
      eq(ffi.string(argv[0]), '/bin/bash')
      eq(ffi.string(argv[1]), '-c')
      eq(ffi.string(argv[2]), '(echo ^&^|^<^>^(^)^@^^)')
      eq(nil, argv[3])
    end)

    itp('applies shellxquote="(', function()
      cimported.p_sxq = to_cstr('"(')
      cimported.p_sxe = to_cstr('"&|<>()@^')

      local argv = ffi.cast('char**', cimported.shell_build_argv(
                                          to_cstr('echo -n some text'), nil))
      eq(ffi.string(argv[0]), '/bin/bash')
      eq(ffi.string(argv[1]), '-c')
      eq(ffi.string(argv[2]), '"(echo -n some text)"')
      eq(nil, argv[3])
    end)

    itp('applies shellxquote="', function()
      cimported.p_sxq = to_cstr('"')
      cimported.p_sxe = to_cstr('')

      local argv = ffi.cast('char**', cimported.shell_build_argv(
                                          to_cstr('echo -n some text'), nil))
      eq(ffi.string(argv[0]), '/bin/bash')
      eq(ffi.string(argv[1]), '-c')
      eq(ffi.string(argv[2]), '"echo -n some text"')
      eq(nil, argv[3])
    end)

    itp('with empty shellxquote/shellxescape', function()
      local argv = ffi.cast('char**', cimported.shell_build_argv(
                                          to_cstr('echo -n some text'), nil))
      eq(ffi.string(argv[0]), '/bin/bash')
      eq(ffi.string(argv[1]), '-c')
      eq(ffi.string(argv[2]), 'echo -n some text')
      eq(nil, argv[3])
    end)
  end)
end)
