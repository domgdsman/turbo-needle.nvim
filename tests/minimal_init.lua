local plenary_dir = os.getenv("PLENARY_DIR") or "/tmp/plenary.nvim"
local plenary_commit = "3707cdb1e43f5cea73afb6037e6494e7ce847a66"
local is_not_a_directory = vim.fn.isdirectory(plenary_dir) == 0

if is_not_a_directory then
	vim.fn.system({ "git", "clone", "https://github.com/nvim-lua/plenary.nvim", plenary_dir })
end

if vim.fn.isdirectory(plenary_dir .. "/.git") == 1 then
	vim.fn.system({ "git", "-C", plenary_dir, "fetch", "--depth", "1", "origin", plenary_commit })
	vim.fn.system({ "git", "-C", plenary_dir, "checkout", "--detach", plenary_commit })
end

vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)

vim.cmd("runtime plugin/plenary.vim")
require("plenary.busted")
