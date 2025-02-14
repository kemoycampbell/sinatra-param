require 'sinatra/base'
require 'sinatra/param/version'
require 'date'
require 'time'

module Sinatra
  module Param
    Boolean = :boolean

    class InvalidParameterError < StandardError
      attr_accessor :param, :options
    end

    def param(name, type, options = {})
      name = name.to_s

      return unless params.member?(name) or options.has_key?(:default) or options[:required]

      begin
        params[name] = coerce(params[name], type, options)
        params[name] = (options[:default].call if options[:default].respond_to?(:call)) || options[:default] if params[name].nil? and options.has_key?(:default)
        params[name] = options[:transform].to_proc.call(params[name]) if params[name] and options[:transform]
        validate!(params[name], options, name)
        params[name]
      rescue InvalidParameterError => exception
        if options[:raise] or (settings.raise_sinatra_param_exceptions rescue false)
          exception.param, exception.options = name, options
          raise exception
        end

        error = options[:message] || exception.to_s

        if content_type and content_type.match(mime_type(:json))
          error = {message: error, errors: {name => exception.message}}.to_json
        else
          content_type 'text/plain'
        end

        halt 400, error
      end
    end

    def one_of(*args)
      options = args.last.is_a?(Hash) ? args.pop : {}
      names = args.collect(&:to_s)

      return unless names.length >= 2

      begin
        validate_one_of!(params, names, options)
      rescue InvalidParameterError => exception
        if options[:raise] or (settings.raise_sinatra_param_exceptions rescue false)
          exception.param, exception.options = names, options
          raise exception
        end

        error = "Invalid parameters [#{names.join(', ')}]"
        if content_type and content_type.match(mime_type(:json))
          error = {message: error, errors: {names => exception.message}}.to_json
        end

        halt 400, error
      end
    end

    def any_of(*args)
      options = args.last.is_a?(Hash) ? args.pop : {}
      names = args.collect(&:to_s)

      return unless names.length >= 2

      begin
        validate_any_of!(params, names, options)
      rescue InvalidParameterError => exception
        if options[:raise] or (settings.raise_sinatra_param_exceptions rescue false)
          exception.param, exception.options = names, options
          raise exception
        end

        error = "Invalid parameters [#{names.join(', ')}]"
        if content_type and content_type.match(mime_type(:json))
          error = {message: error, errors: {names => exception.message}}.to_json
        end

        halt 400, error
      end
    end

    def all_or_none_of(*args)
      options = args.last.is_a?(Hash) ? args.pop : {}
      names = args.collect(&:to_s)

     begin
        validate_all_or_none_of!(params, names, options)
      rescue InvalidParameterError => exception
        if options[:raise] or (settings.raise_sinatra_param_exceptions rescue false)
          exception.param, exception.options = names, options
          raise exception
        end

        error = "Invalid parameters [#{names.join(', ')}]"
        if content_type and content_type.match(mime_type(:json))
          error = {message: error, errors: {names => exception.message}}.to_json
        end

        halt 400, error
      end
    end

    private

    def coerce(param, type, options = {})
      begin
        return nil if param.nil?
        return param if (param.is_a?(type) rescue false)
        return Integer(param, 10) if type == Integer
        return Float(param) if type == Float
        return String(param) if type == String
        return Date.parse(param) if type == Date
        return Time.parse(param) if type == Time
        return DateTime.parse(param) if type == DateTime
        return Array(param.split(options[:delimiter] || ",")) if type == Array
        return Hash[param.split(options[:delimiter] || ",").map{|c| c.split(options[:separator] || ":")}] if type == Hash
        if [TrueClass, FalseClass, Boolean].include? type
          coerced = /^(false|f|no|n|0)$/i === param.to_s ? false : /^(true|t|yes|y|1)$/i === param.to_s ? true : nil
          raise ArgumentError if coerced.nil?
          return coerced
        end
        return nil
      rescue ArgumentError
        raise InvalidParameterError, "'#{param}' is not a valid #{type}"
      end
    end

    def validate!(param, options, name)
      options.each do |key, value|
        case key
        when :required
          raise InvalidParameterError, "The parameter #{name} is required" if value && param.nil?
        when :blank
          raise InvalidParameterError, "The parameter #{name} cannot be blank" if !value && case param
          when String
            !(/\S/ === param)
          when Array, Hash
            param.empty?
          else
            param.nil?
          end
        when :format
          raise InvalidParameterError, "The parameter #{name} must be a string if using the format validation" unless param.kind_of?(String)
          raise InvalidParameterError, "The parameter #{name} must match format #{value}" unless param =~ value
        when :is
          raise InvalidParameterError, "The parameter #{name} must be #{value}" unless param === value
        when :in, :within, :range
          raise InvalidParameterError, "The parameter #{name} must be within #{value}" unless param.nil? || case value
          when Range
            value.include?(param)
          else
            Array(value).include?(param)
          end
        when :min
          raise InvalidParameterError, "The parameter #{name} cannot be less than #{value}" unless param.nil? || value <= param
        when :max
          raise InvalidParameterError, "The parameter #{name} cannot be greater than #{value}" unless param.nil? || value >= param
        when :min_length
          raise InvalidParameterError, "The parameter #{name} cannot have length less than #{value}" unless param.nil? || value <= param.length
        when :max_length
          raise InvalidParameterError, "The parameter #{name} cannot have length greater than #{value}" unless param.nil? || value >= param.length
        end
      end
    end

    def validate_one_of!(params, names, options)
      raise InvalidParameterError, "Only one of [#{names.join(', ')}] is allowed" if names.count{|name| present?(params[name])} > 1
    end

    def validate_any_of!(params, names, options)
      raise InvalidParameterError, "One of parameters [#{names.join(', ')}] is required" if names.count{|name| present?(params[name])} < 1
    end

    def validate_all_or_none_of!(params, names, options)
      present_count = names.count{|name| present?(params[name])}
      raise InvalidParameterError, "All or none of parameters [#{names.join(', ')}] are required" if present_count > 0 and present_count != names.length
    end

    # ActiveSupport #present? and #blank? without patching Object
    def present?(object)
      !blank?(object)
    end

    def blank?(object)
      object.respond_to?(:empty?) ? object.empty? : !object
    end
  end

  helpers Param
end
