if vim.g.loaded_turbo_needle then
  return
end

vim.g.loaded_turbo_needle = 1

local turbo_needle = require('turbo-needle')

vim.api.nvim_create_user_command('TurboNeedle', function(opts)
	local subcmd = opts.args
	if subcmd == 'enable' then
		turbo_needle.enable()
	elseif subcmd == 'disable' then
		turbo_needle.disable()
	else
		vim.notify('TurboNeedle: Invalid subcommand. Use "enable" or "disable"', vim.log.levels.ERROR)
	end
end, {
	nargs = 1,
	desc = 'Control turbo-needle completions: enable/disable',
	complete = function()
		return { 'enable', 'disable' }
	end
})