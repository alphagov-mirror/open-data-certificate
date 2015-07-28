require 'pry'

class Flow

  # will generate a flow chart based on the path that can be navigated through the
  # entire scope of the certificates (legal and practical)

  def initialize(jurisdiction, type, debugPath = false)
    if debugPath
      path = File.join(Rails.root, 'fixtures', "test.legal.xml")
    else
      path = get_path(jurisdiction, type)
    end
    # two Nokogiri parses are created because the operations & transformations exacted destructively modify data
    @xml = Nokogiri::XML(File.open(path))
    @xml_copy = Nokogiri::XML(File.open(path))
    # marshals XML into two above hashes

  end

  def get_path(jurisdiction, type)
    # return two different paths based on whether legal or practical question flow selected
    jurisdiction = "en" if (jurisdiction == "gb" && type == "Practical")
    jurisdiction.upcase! if type == "Legal" # check what this bang! means
    folder = folder_name(type)
    path = File.join(Rails.root, 'prototype', folder, "certificate.#{jurisdiction}.xml")
    unless File.exist?(path)
      path = File.join(Rails.root, 'prototype', folder, "certificate.en.xml")
    end
    path
  end

  def folder_name(type)
    # used for retreiving the file to be parsed
    {
      "Legal" => "jurisdictions",
      "Practical" => "translations"
    }[type]
  end

  def questions
    @xml_copy.xpath("//if").remove # remove any dependencies
    @xml_copy.xpath("//question").map do |q|
      question(q)
    end
    # should return an array of hashes? TEST
  end

  def dependencies
    @xml.xpath("//if//question").map do |q|
      question(q, true)
    end
    # should return an array of hashes? TEST
  end

  def question(q, dependency = true)
    # q => Nokogiri::XML::Element , should be FALSE???
    # returns a hash
    {
      id: q["id"],
      label: label(q),
      type: type(q),
      level: level(q),
      answers: answers(q), # array of hashes
      prerequisites: dependency === true ? prerequisites(q) : nil
      # assign prerequisite to the method if dependency is true or nil depending or nil if false
      # Left is true, right is false
    }
  end

  def answers(question)
    # returns result of dependency method, or an array of hashes based on input type
    # hash is usually a single key=> value assignment
    if type(question) == "yesno"
      {
        "true" => {
          dependency: dependency(question, "true")
        },
        "false" => {
          dependency: dependency(question, "false")
        }
      }
    elsif question.at_xpath("radioset|checkboxset")
      answers = {}
      question.at_xpath("radioset|checkboxset").xpath("option").each do |option|
        answers[option.at_xpath("label").text] = {
          dependency: dependency(question, option["value"])
        }
      end
      answers
    elsif question.at_xpath("select")
      answers = {}
      question.at_xpath("select").xpath("option").each do |option|
        next if option["value"].nil?
        answers[option.text] = {
          dependency: dependency(question, option["value"])
        }
      end
      answers
    end
  end

  def label(question)
    CGI.unescapeHTML(question.at_xpath("label").text).gsub("\"", "'")
  end

  def type(question)
    # determines and returns the type of input field is associated with XML
    if question.at_xpath("input")
      "input"
    elsif question.at_xpath("yesno")
      "yesno"
    elsif question.at_xpath("radioset")
      "radioset"
    elsif question.at_xpath("checkboxset")
      "checkboxset"
    end
  end

  def level(question)
    # this identifies which order of merit is indicated by the level attached to the question
    question.at_xpath("requirement")["level"] unless question.at_xpath("requirement").nil?
  end

  def dependency(question, answer)
    dependency = @xml.xpath("//if[contains(@test, \"this.#{question["id"]}() === '#{answer}'\")]").at_css("question")
    dependency["id"] unless dependency.nil?
  end

  def prerequisites(question)
    # question => Nokogiri::XML::Element
    # returns String or nil
    test = question.parent["test"] || question.parent.parent["test"]  # returns a String
    test.scan(/this\.([a-z]+)\(\)/i).map { |s| s[0] } unless test.nil?
    # this regex is scanning for `this.*xmlDependencyMethod*()`
    # it returns an array of count 1 with a String of the *xmlDependencyMethod*() searched for
  end

end
