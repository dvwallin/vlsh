module main

import os
import net.http
import term
import readline { Readline }

import cmds
import exec
import utils

const (
	config_file  = [os.home_dir(), '.vlshrc'].join('/')
	version		 = '0.1.2'
)

struct Cfg {
	mut:
	paths []string
	aliases map[string]string
}

fn read_cfg() ?Cfg {
	mut cfg := Cfg{}
	config_file_data := os.read_lines(config_file) ?
	cfg.extract_aliases(config_file_data)
	cfg.extract_paths(config_file_data) or {
		return err
	}
	utils.debug(cfg)

	return cfg
}

fn main() {
	term.clear()
	mut r := Readline{}
	r.enable_raw_mode()
	for {
		mut current_dir := term.colorize(term.bold, '$os.getwd() ')
		current_dir = current_dir.replace('$os.home_dir()', '~')
		git_branch_output := utils.get_git_info()
		println('\n$git_branch_output\n$current_dir')
		cmd := r.read_line_utf8(term.red(':=')) or {
			utils.fail(err.msg)
			return
		}
		main_loop(cmd.str().trim_space())
	}
	r.disable_raw_mode()
}

fn main_loop(input string) {

	input_split := input.split(' ')
	cmd := input_split[0]
	mut args := []string{}
	if input_split.len > 1 {
		args << input_split[1..]
	}

	// reading in configuration file to handle paths and aliases
	mut cfg := read_cfg() or {
		utils.fail('could not read $config_file')
		return
	}

	match cmd {
		'aliases' {
			for alias_name, alias_cmd in cfg.aliases {
				print('${term.bold(alias_name)} : ${term.italic(alias_cmd)}\n')
			}
		}
		'cd' {
			cmds.cd(args)
		}
		'ocp' {
			cmds.ocp(args) or {
				utils.fail(err.msg)
			}
		}
		'exit' {
			exit(0)
		}
		'help' {
			cmds.help(version)
		}
		'version' {
			println('version $version')
		}
		'source' {
			cfg = read_cfg() or {
				utils.fail('could not read $config_file')
				return
			}
		}
		'share' {
			println('args: $args')
			if args.len != 1 {
				utils.warn('usage: share <file>')
				return
			}
			if !os.exists(args[0]) {
				utils.fail('could not find ${args[0]}')
				return
			}
			file_content := os.read_file(args[0]) or {
				utils.fail('could not read ${args[0]}')
				return
			}

			mut data := map[string]string
			host := 'https://dpaste.com/api/'
			data['content'] = file_content
			resp := http.post_form(host, data) or {
				utils.fail('could not post file: ${err.msg}')
				return
			}

			if resp.status_code == 200 || resp.status_code == 201 {
				utils.ok('file uploaded to: ${resp.text}')
				return
			}
			utils.fail('status_code: ${resp.status_code}')
			utils.debug(resp)
			return
		}
		else {
			mut t := exec.Task{
				cmd: exec.Cmd_object{
					cmd: cmd,
					args: args,
					aliases: cfg.aliases,
					paths: cfg.paths
				}
			}
			t.prepare_task() or {
				utils.fail(err.msg)
			}
		}
	}
}

fn (mut cfg Cfg) extract_aliases(config []string) {
	for ent in config {
		if ent[0..5].trim_space() == 'alias' {
			split_alias := ent.replace('alias', '').trim_space().split('=')
			cfg.aliases[split_alias[0]] = split_alias[1]
		}
	}
}

fn (mut cfg Cfg) extract_paths(config []string) ? {
	for ent in config {
		if ent[0..4].trim_space() == 'path' {
			cleaned_ent := ent.replace('path', '').replace('=', '')
			mut split_paths := cleaned_ent.trim_space().split(';')
			for mut path in split_paths {
				path = path.trim_right('/')
				if os.exists(os.real_path(path)) {
					cfg.paths << path
				} else {
					real_path := os.real_path(path)
					return error('could not find ${real_path}')
				}
			}
		}
	}
}
