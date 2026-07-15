# Testes em paralelo forkam workers (parallelize). No macOS, o libpq carrega o
# GSS.framework (Objective-C, que não é fork-safe) na 1ª conexão — o fork depois
# disso faz o pg segfaultar em connect_start. Desligar o GSS ANTES de qualquer
# conexão (precisa vir antes de carregar o environment) evita o crash. Só teste.
ENV["PGGSSENCMODE"] ||= "disable"

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

# Compila os assets do Vite UMA vez no processo pai, ANTES de o parallelize forkar
# os workers. Sem isto, o 1º render Inertia de cada worker dispara o auto_build do
# Vite em paralelo e um worker às vezes lê o manifest a meio ("Vite Ruby can't
# find ... in the manifests"). Guardado por digest: no-op quando os fontes não mudam.
ViteRuby.commands.build if defined?(ViteRuby)

require "rails/test_help"
require "inertia_rails/minitest" # assert_inertia_component / inertia.props nos testes de tela
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
