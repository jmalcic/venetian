# frozen_string_literal: true

require "venetian/version"
require "venetian/upstream"
require "venetian/executable"
require "venetian/browser_installer"
require "venetian/gemspec"

module Venetian
  class << self
    attr_accessor :auto_install_dependencies
  end

  class Error < StandardError; end

  self.auto_install_dependencies = true

  def self.execute(*, echo: true, **)
    Executable.execute(*, echo: echo, **)
  end

  def self.system(*, echo: true, **)
    Executable.system(*, echo: echo, **)
  end
end
