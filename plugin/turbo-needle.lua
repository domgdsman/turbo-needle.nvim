if vim.g.loaded_turbo_needle then
  return
end

vim.g.loaded_turbo_needle = 1

local turbo_needle = require('turbo-needle')

vim.api.nvim_create_user_command('TurboNeedleSetup', function()
   turbo_needle.setup()
end, {
   desc = 'Setup turbo-needle plugin with default configuration'
})