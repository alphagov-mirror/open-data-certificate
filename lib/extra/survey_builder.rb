# for building surveys from delayed job
class SurveyBuilder < Struct.new(:dir, :basename)

  def perform
    survey_parsing = SurveyParsing.find_or_create_by_file_name(path)
    survey_parsing.compute_digest!

    changed = survey_parsing.changed? && survey_parsing.save
    rebuild = changed || ENV['FORCE_REBUILD'].present?

    record_event "SurveyBuilder: #{dir}/#{basename} - #{rebuild ? 'building' : 'skipping '} - #{survey_parsing.md5}"

    if rebuild
      survey = parse_file
      survey.set_expired_certificates
    end

    changed
  end

  def build_priority
    stub = ParseStub.new
    stub.instance_eval(file_contents)
    return 1 if stub.name == Survey::DEFAULT_ACCESS_CODE
    return 2 if stub.args[0][:status].to_s == 'beta'
    return 3
  end

  # Parse code taken from surveyor to allow the survey object to be returned
  def parse_file(options={})
    str = file_contents
    Surveyor::Parser.ensure_attrs
    Surveyor::Parser.options = {filename: file}.merge(options)
    Surveyor::Parser.log[:source] = str
    Surveyor::Parser.rake_trace "\n"
    survey = Surveyor::Parser.new.parse(str)
    Surveyor::Parser.rake_trace "\n"
    survey
  end

  def error(job, exception)
    record_event "error - #{basename}"
    Airbrake.notify(exception) if defined? Airbrake
  end

  private

  def record_event message
    DevEvent.create message: message
    puts message unless Rails.env.test?
  end

  # a stub parser to collect the name of the survey
  class ParseStub
    attr_reader :name, :args
    def survey(name, *args, &block)
      # match surveyor name->access_code
      @name = name.to_s.downcase.gsub(/[^a-z0-9]/,"-").gsub(/-+/,"-").gsub(/-$|^-/,"")
      @args = args
    end
  end

  def file_contents
    File.read(file)
  end

  def file
    Rails.root.join(path)
  end

  def path
    Pathname.new(dir).join(basename).to_s
  end

end
