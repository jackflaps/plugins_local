class MARCModel < ASpaceExport::ExportModel
  model_for :marc21

  include JSONModel

  def self.df_handler(name, tag, ind1, ind2, code)
    define_method(name) do |val|
      df(tag, ind1, ind2).with_sfs([code, val])
    end
    name.to_sym
  end

  @archival_object_map = {
    :repository => :handle_repo_code,
    :title => :handle_title,
    :linked_agents => :handle_agents,
    :subjects => :handle_subjects,
    :extents => :handle_extents,
    :language => :handle_language,
    :external_documents => :handle_documents,
    :dates => :handle_dates,
  }

  @resource_map = {
    [:id_0, :id_1, :id_2, :id_3] => :handle_id,
    :notes => :handle_notes,
    :finding_aid_description_rules => df_handler('fadr', '040', ' ', ' ', 'e'),
    :uri => :handle_url,
    :user_defined => :handle_user_defined # Local customization: export user-defined strings
  }

  attr_accessor :leader_string
  attr_accessor :controlfield_string
  attr_accessor :local_controlfield_string # Local customization: create attribute for 001 field

  @@datafield = Class.new do

    attr_accessor :tag
    attr_accessor :ind1
    attr_accessor :ind2
    attr_accessor :subfields


    def initialize(*args)
      @tag, @ind1, @ind2 = *args
      @subfields = []
    end

    def with_sfs(*sfs)
      sfs.each do |sf|
        subfield = @@subfield.new(*sf)
        @subfields << subfield unless subfield.empty?
      end

      return self
    end

  end

  @@subfield = Class.new do

    attr_accessor :code
    attr_accessor :text

    def initialize(*args)
      @code, @text = *args
    end

    def empty?
      if @text && !@text.empty?
        false
      else
        true
      end
    end
  end

  def initialize
    @datafields = {}
  end

  def datafields
    @datafields.map {|k,v| v}
  end


  def self.from_aspace_object(obj)
    self.new
  end

  # 'archival object's in the abstract
  def self.from_archival_object(obj)

    marc = self.from_aspace_object(obj)

    marc.apply_map(obj, @archival_object_map)

    marc
  end

  # subtypes of 'archival object':

  def self.from_resource(obj)
    marc = self.from_archival_object(obj)
    marc.apply_map(obj, @resource_map)
    marc.leader_string = "00000np$aa2200000 i 4500"
    marc.leader_string[7] = obj.level == 'item' ? 'm' : 'c'

    marc.controlfield_string = assemble_controlfield_string(obj)

    ## BEGIN local customization: obj.user_defined.string_2 == Alma MMS ID
    if obj.has_key?('user_defined')
      marc.local_controlfield_string = obj['user_defined']['string_2'] if obj['user_defined'].has_key?('string_2')
    end
    ## END

    ## BEGIN local customization: hard-coded RDA 33x field defaults
    marc.df('336', ' ', ' ').with_sfs(['a', 'other'], ['b', 'xxx'], ['2', 'rdacontent'])
    marc.df('337', ' ', ' ').with_sfs(['a', 'unmediated'], ['b', 'n'], ['2', 'rdamedia'])
    marc.df('338', ' ', ' ').with_sfs(['a', 'other'], ['b', 'nz'], ['2', 'rdacarrier'])
    ## END

    marc
  end


  def self.assemble_controlfield_string(obj)
    date = obj.dates[0] || {}
    string = obj['system_mtime'].scan(/\d{2}/)[1..3].join('')
    string += obj.level == 'item' && date['date_type'] == 'single' ? 's' : 'i'
    string += date['begin'] ? date['begin'][0..3] : "    "
    string += date['end'] ? date['end'][0..3] : "    "
    string += "xx"
    18.times { string += ' ' }
    string += (obj.language || '|||')
    string += ' d'

    string
  end


  def df!(*args)
    @sequence ||= 0
    @sequence += 1
    @datafields[@sequence] = @@datafield.new(*args)
    @datafields[@sequence]
  end


  def df(*args)
    if @datafields.has_key?(args.to_s)
      @datafields[args.to_s]
    else
      @datafields[args.to_s] = @@datafield.new(*args)
      @datafields[args.to_s]
    end
  end


  def handle_id(*ids)
    ids.reject!{|i| i.nil? || i.empty?}

    ## BEGIN local customization: local formatting of MS call numbers
    df('099', ' ', '9').with_sfs(['a', "MS #{ids.join('.')}"])
    ## END

  end


  def handle_title(title)
    df('245', '1', '0').with_sfs(['a', title])
  end

  def handle_language(langcode)
    return false unless langcode
    df('041', '0', ' ').with_sfs(['a', langcode])
  end


  def handle_dates(dates)
    return false if dates.empty?

    dates = [["single", "inclusive", "range"], ["bulk"]].map {|types|
      dates.find {|date| types.include? date['date_type'] }
    }.compact

    dates.each do |date|
      code = date['date_type'] == 'bulk' ? 'g' : 'f'
      val = nil
      if date['expression'] && date['date_type'] != 'bulk'
        val = date['expression']
      elsif date['date_type'] == 'single'
        val = date['begin']
      else
        val = "#{date['begin']}-#{date['end']}"
      end

      df('245', '1', '0').with_sfs([code, val])

      ## BEGIN local customization: don't export the date if it's not yet determined
      if code == 'f' && val != 'Date Not Yet Determined'
        df('264', ' ', '0').with_sfs(['c', val])
      end
      ## END
    end
  end

  def handle_repo_code(repository)
    repo = repository['_resolved']
    return false unless repo

    sfa = repo['org_code'] ? repo['org_code'] : "Repository: #{repo['repo_code']}"

    ## BEGIN local customizations:
    # * drop repo name from 852|b
    # * use our OCLC code instead of our MARC code in the 040
    df('852', '4', '1').with_sfs(['a', sfa])
    df('040', ' ', ' ').with_sfs(['a', 'DVP'], ['b', 'eng'], ['c', 'DVP'])
    ## END
  end

  def source_to_code(source)
    ASpaceMappings::MARC21.get_marc_source_code(source)
  end

  def handle_subjects(subjects)
    subjects.each do |link|
      subject = link['_resolved']
      term, *terms = subject['terms']
      code, ind2 =  case term['term_type']
                    when 'uniform_title'
                      ['630', source_to_code(subject['source'])]
                    when 'temporal'
                      ['648', source_to_code(subject['source'])]

                    ## BEGIN local customization: A hack to export headings for buildings as 610s (pt. 1)
                    when 'topical'
                      if subject['source'] == 'built'
                        ['610', '7']
                      else
                        ['650', source_to_code(subject['source'])]
                      end
                    ## END
                    when 'geographic', 'cultural_context'
                      ['651', source_to_code(subject['source'])]
                    when 'genre_form', 'style_period'
                      ['655', source_to_code(subject['source'])]
                    when 'occupation'
                      ['656', '7']
                    when 'function'
                      ['657', '7']
                    else
                      ['650', source_to_code(subject['source'])]
                    end
      sfs = [['a', term['term']]]

      terms.each do |t|
        tag = case t['term_type']
              when 'uniform_title'; 't'
              when 'genre_form', 'style_period'; 'v'
              when 'topical', 'cultural_context', 'occupation'; 'x'
              when 'temporal'; 'y'
              when 'geographic'; 'z'
              end
        sfs << [tag, t['term']]
      end

      ## BEGIN local customization: A hack to export headings for buildings as 610s (pt. 2)
      if ind2 == '7'
        if subject['source'] == 'built'
          sfs << ['2', 'local']
        else
          sfs << ['2', subject['source']]
        end
      end
      ## END

      df!(code, ' ', ind2).with_sfs(*sfs)
    end
  end


  def handle_primary_creator(linked_agents)
    link = linked_agents.find{|a| a['role'] == 'creator'}
    return nil unless link

    creator = link['_resolved']
    name = creator['display_name']
    ind2 = ' '
    role_info = link['relator'] ? ['4', link['relator']] : ['e', 'creator']

    case creator['agent_type']

    when 'agent_corporate_entity'
      code = '110'
      ind1 = '2'
      sfs = [
              ['a', name['primary_name']],
              ['b', name['subordinate_name_1']],
              ['b', name['subordinate_name_2']],
              ['n', name['number']],
              ['d', name['dates']],
              ['g', name['qualifier']],
            ]

    when 'agent_person'
      joint, ind1 = name['name_order'] == 'direct' ? [' ', '0'] : [', ', '1']
      name_parts = [name['primary_name'], name['rest_of_name']].reject{|i| i.nil? || i.empty?}.join(joint)

      code = '100'
      sfs = [
              ['a', name_parts],
              ['b', name['number']],
              ['c', %w(prefix title suffix).map {|prt| name[prt]}.compact.join(', ')],
              ['q', name['fuller_form']],
              ['d', name['dates']],
              ['g', name['qualifier']],
            ]

    when 'agent_family'
      code = '100'
      ind1 = '3'
      sfs = [
              ['a', name['family_name']],
              ['c', name['prefix']],
              ['d', name['dates']],
              ['g', name['qualifier']],
            ]
    end

    sfs << role_info
    df(code, ind1, ind2).with_sfs(*sfs)
  end


  def handle_agents(linked_agents)
    handle_primary_creator(linked_agents)

    subjects = linked_agents.select{|a| a['role'] == 'subject'}

    subjects.each_with_index do |link, i|
      subject = link['_resolved']
      name = subject['display_name']
      relator = link['relator']
      terms = link['terms']
      ind2 = source_to_code(name['source'])

      case subject['agent_type']

      when 'agent_corporate_entity'
        code = '610'
        ind1 = '2'
        sfs = [
                ['a', name['primary_name']],
                ['b', name['subordinate_name_1']],
                ['b', name['subordinate_name_2']],
                ['n', name['number']],
                ['g', name['qualifier']],
              ]

      when 'agent_person'
        joint, ind1 = name['name_order'] == 'direct' ? [' ', '0'] : [', ', '1']
        name_parts = [name['primary_name'], name['rest_of_name']].reject{|i| i.nil? || i.empty?}.join(joint)
        ind1 = name['name_order'] == 'direct' ? '0' : '1'
        code = '600'
        sfs = [
                ['a', name_parts],
                ['b', name['number']],
                ['c', %w(prefix title suffix).map {|prt| name[prt]}.compact.join(', ')],
                ['q', name['fuller_form']],
                ['d', name['dates']],
                ['g', name['qualifier']],
              ]

      when 'agent_family'
        code = '600'
        ind1 = '3'
        sfs = [
                ['a', name['family_name']],
                ['c', name['prefix']],
                ['d', name['dates']],
                ['g', name['qualifier']],
              ]

      end

      terms.each do |t|
        tag = case t['term_type']
          when 'uniform_title'; 't'
          when 'genre_form', 'style_period'; 'v'
          when 'topical', 'cultural_context', 'occupation'; 'x'
          when 'temporal'; 'y'
          when 'geographic'; 'z'
          end
        sfs << [(tag), t['term']]
      end

      if ind2 == '7'
        sfs << ['2', subject['source']]
      end

      df(code, ind1, ind2, i).with_sfs(*sfs)
    end


    creators = linked_agents.select{|a| a['role'] == 'creator'}[1..-1] || []
    creators = creators + linked_agents.select{|a| a['role'] == 'source'}

    # this fixes a bug where all 7xx fields of a single agent type exported into one datafield
    creators.each_with_index do |link, i|
      creator = link['_resolved']
      name = creator['display_name']
      relator = link['relator']
      terms = link['terms']
      role = link['role']

      if relator
        relator_sf = ['e', I18n.t("enumerations.linked_agent_archival_record_relators.#{relator}").downcase]
      elsif role == 'source'
        relator_sf =  ['e', 'former owner']
      else
        relator_sf = ['e', 'creator']
      end

      ind2 = ' '

      case creator['agent_type']

      when 'agent_corporate_entity'
        code = '710'
        ind1 = '2'
        sfs = [
                ['a', name['primary_name']],
                ['b', name['subordinate_name_1']],
                ['b', name['subordinate_name_2']],
                ['n', name['number']],
                ['g', name['qualifier']],
              ]

      when 'agent_person'
        joint, ind1 = name['name_order'] == 'direct' ? [' ', '0'] : [', ', '1']
        name_parts = [name['primary_name'], name['rest_of_name']].reject{|i| i.nil? || i.empty?}.join(joint)
        ind1 = name['name_order'] == 'direct' ? '0' : '1'
        code = '700'
        sfs = [
                ['a', name_parts],
                ['b', name['number']],
                ['c', %w(prefix title suffix).map {|prt| name[prt]}.compact.join(', ')],
                ['q', name['fuller_form']],
                ['d', name['dates']],
                ['g', name['qualifier']],
              ]

      when 'agent_family'
        ind1 = '3'
        code = '700'
        sfs = [
                ['a', name['family_name']],
                ['c', name['prefix']],
                ['d', name['dates']],
                ['g', name['qualifier']],
              ]

      end

      sfs << relator_sf
      df(code, ind1, ind2, i).with_sfs(*sfs)
    end

  end


  def handle_notes(notes)
    notes.each do |note|
      if note['publish']
        prefix =  case note['type']
                  when 'dimensions'; "Dimensions"
                  when 'physdesc'; "Physical Description note"
                  when 'materialspec'; "Material Specific Details"
                  when 'physloc'; "Location of resource"
                  when 'phystech'; "Physical Characteristics / Technical Requirements"
                  when 'physfacet'; "Physical Facet"
                  when 'processinfo'; "Processing Information"
                  when 'separatedmaterial'; "Materials Separated from the Resource"
                  else; nil
                  end

        marc_args = case note['type']
                    when 'arrangement', 'fileplan'
                      ['351','b']
                    when 'odd', 'dimensions', 'physdesc', 'materialspec', 'physloc', 'phystech', 'physfacet', 'processinfo', 'separatedmaterial'
                      ['500','a']
                    when 'accessrestrict'
                      ['506','a']
                    when 'scopecontent'
                      ['520', '2', ' ', 'a']
                    when 'abstract'
                      ['520', '3', ' ', 'a']
                    when 'prefercite'
                      ['524', '8', ' ', 'a']
                    when 'acqinfo'
                      ind1 = note['publish'] ? '1' : '0'
                      ['541', ind1, ' ', 'a']
                    when 'relatedmaterial'
                      ['544','a']
                    when 'bioghist'
                      ['545','a']
                    when 'custodhist'
                      ind1 = note['publish'] ? '1' : '0'
                      ['561', ind1, ' ', 'a']
                    when 'appraisal'
                      ind1 = note['publish'] ? '1' : '0'
                      ['583', ind1, ' ', 'a']
                    when 'accruals'
                      ['584', 'a']
                    when 'altformavail'
                      ['535', '2', ' ', 'a']
                    when 'originalsloc'
                      ['535', '1', ' ', 'a']
                    when 'userestrict', 'legalstatus'
                      ['540', 'a']
                    when 'langmaterial'
                      ['546', 'a']
                    else
                      nil
                    end

        unless marc_args.nil?
          text = prefix ? "#{prefix}: " : ""
          text += ASpaceExport::Utils.extract_note_text(note)
          df!(*marc_args[0...-1]).with_sfs([marc_args.last, *Array(text)]) unless text.empty?
        end
      end
    end
  end


  def handle_extents(extents)
    extents.each do |ext|
      e = ext['number']
      e << " #{I18n.t('enumerations.extent_extent_type.'+ext['extent_type'], :default => ext['extent_type'])}"

      if ext['container_summary']
        e << " (#{ext['container_summary']})"
      end

      ## BEGIN local customization: export dimensions into 300|c subfield
      if ext['dimensions']
        d = ext['dimensions']
      end

      df!('300').with_sfs(['a', e], ['c', d])
      ## END
    end
  end


  ## BEGIN local customization: external_documents handler for Islandora links
  def handle_documents(documents)
    documents.each do |doc|
      case doc['title']
        when 'Special Collections @ DU'
          df('856', '4', '1').with_sfs(
            ['z', "Access collection materials in Special Collections @ DU"],
            ['u', doc['location']]
          )
        else
          nil
      end
    end
  end
  ## END


  def handle_url(uri)
    text =
    df('856', '4', '2').with_sfs(
      ['z', "Finding aid available"],
      ['u', "https://duarchives.coalliance.org#{uri}"]
    )
  end

  ## BEGIN local customization: handle user-defined strings as such:
  # obj.user_defined.string_3 = OCLC number
  def handle_user_defined(user_defined)
    return false unless user_defined
    if user_defined.has_key?('string_3')
      text = "(OCoLC)"
      text += user_defined['string_3'].delete("http://worldcat.org/oclc/")
      df('035', ' ', ' ').with_sfs(['a', text])
    end
  end
  ## END

end
