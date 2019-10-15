# This include is for all of the defaults encoded in the MARCModel that we
# override locally for reasons about which we don't feel strongly enough to
# submit pull requests to core.
#
# Other customizations are in our decorator: denver_marc_serializer.rb

class MARCModel < ASpaceExport::ExportModel
  attr_reader :aspace_record
  attr_accessor :controlfields

  # wondering if I can put finding_aid_description_rules here...
  @archival_object_map = {
    [:repository, :finding_aid_language, :finding_aid_description_rules] => :handle_repo_code
  }

  # we don't use the ead_loc method because we use the PUI for "finding aids"
  @resource_map = {
    [:id_0, :id_1, :id_2, :id_3] => :handle_id,
    :notes => :handle_notes
  }

  def initialize(obj, opts = {include_unpublished: false})
    @datafields = {}
    @controlfields = {}
    @include_unpublished = opts[:include_unpublished]
    @aspace_record = obj
  end

  def include_unpublished?
    @include_unpublished
  end

  def self.from_aspace_object(obj, opts = {})
    self.new(obj, opts)
  end

  def handle_repo_code(repository, *finding_aid_language, finding_aid_description_rules)
    repo = repository['_resolved']
    return false unless repo

    sfa = repo['org_code'] ? repo['org_code'] : "Repository: #{repo['repo_code']}"

    # ANW-529: options for 852 datafield:
    # 1.) $a => org_code || repo_name
    # 2.) $a => $parent_institution_name && $b => repo_name

    if repo['parent_institution_name']
      subfields_852 = [
                        ['a', repo['parent_institution_name']],
                        ['b', repo['name']]
                      ]
    elsif repo['org_code']
      subfields_852 = [
                        ['a', repo['org_code']],
                      ]
    else
      subfields_852 = [
                        ['a', repo['name']]
                      ]
    end

    df('852', ' ', ' ').with_sfs(*subfields_852)
    df('040', ' ', ' ').with_sfs(['a', repo['org_code']], ['b', finding_aid_language[0]], ['e', finding_aid_description_rules], ['c', repo['org_code']])
    df('049', ' ', ' ').with_sfs(['a', repo['org_code']])

    if repo.has_key?('country') && !repo['country'].empty?

      # US is a special case, because ASpace has no knowledge of states, the
      # correct value is 'xxu'
      if repo['country'] == "US"
        df('044', ' ', ' ').with_sfs(['a', "xxu"])
      else
        df('044', ' ', ' ').with_sfs(['a', repo['country'].downcase])
      end
    end
  end

  # prefix 099$a with "MS" per local style guidelines
  def handle_id(*ids)
    ids.reject!{|i| i.nil? || i.empty? }
    df('099', ' ', ' ').with_sfs(['a', "MS #{ids.join('.')}"])
  end

  # if subject['source'] == 'built' export as 610
  # TODO: fix 610$2 == "local" if the real source is Library of Congress (inferred from authority_id)
  def handle_subjects(subjects)
    subjects.each do |link|
      subject = link['_resolved']
      term, *terms = subject['terms']
      code, ind2 =  case term['term_type']
                    when 'uniform_title'
                      ['630', source_to_code(subject['source'])]
                    when 'temporal'
                      ['648', source_to_code(subject['source'])]
                    # LOCAL: hack to export buildings as 610s, part 1
                    when 'topical'
                      if subject['source'] == 'built'
                        ['610', '7']
                      else
                        ['650', source_to_code(subject['source'])]
                      end
                    when 'geographic', 'cultural_context'
                      ['651', source_to_code(subject['source'])]
                    when 'genre_form', 'style_period'
                      ['655', source_to_code(subject['source'])]
                    when 'occupation'
                      ['656', '7']
                    when 'function'
                      ['656', '7']
                    else
                      ['650', source_to_code(subject['source'])]
                    end
      sfs = [['a', term['term']]]

      terms.each do |t|
        tag = case t['term_type']
              when 'uniform_title'; 't'
              when 'genre_form', 'style_period'; 'v'
              # LOCAL: occupation == 'x'
              when 'topical', 'cultural_context', 'occupation'; 'x'
              when 'temporal'; 'y'
              when 'geographic'; 'z'
              end
        sfs << [tag, t['term']]
      end

      # LOCAL: hack to export buildings as 610s, part 2
      if ind2 == '7'
        if subject['source'] == 'built'
          sfs << ['2', 'local']
        else
          sfs << ['2', subject['source']]
        end
      end

      ind1 = code == '630' ? "0" : " "
      df!(code, ind1, ind2).with_sfs(*sfs)
    end
  end

  # export dimensions into 300|c subfield
  def handle_extents(extents)
    extents.each do |ext|
      e = ext['number']
      t =  "#{I18n.t('enumerations.extent_extent_type.'+ext['extent_type'], :default => ext['extent_type'])}"

      if ext['container_summary']
        t << " (#{ext['container_summary']})"
      end

      if ext['dimensions']
        d = ext['dimensions']
      end

      df!('300').with_sfs(['a', e], ['c', d], ['f', t])
    end
  end
end
