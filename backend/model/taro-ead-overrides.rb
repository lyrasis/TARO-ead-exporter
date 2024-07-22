class EADSerializer < ASpaceExport::Serializer
  serializer_for :ead

  def stream(data)
    @stream_handler = ASpaceExport::StreamHandler.new
    @fragments = ASpaceExport::RawXMLHandler.new
    @include_unpublished = data.include_unpublished?
    @include_daos = data.include_daos?
    @use_numbered_c_tags = data.use_numbered_c_tags?
    @id_prefix = I18n.t('archival_object.ref_id_export_prefix', :default => 'aspace_')

    doc = Nokogiri::XML::Builder.new(:encoding => "UTF-8") do |xml|
      begin

      ead_attributes = {
        'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
        'xsi:schemaLocation' => 'urn:isbn:1-931666-22-9 https://www.loc.gov/ead/ead.xsd',
        'xmlns:xlink' => 'http://www.w3.org/1999/xlink'
      }

      if data.publish === false
        ead_attributes['audience'] = 'internal'
      end

      xml.ead( ead_attributes ) {

        xml.text (
          @stream_handler.buffer { |xml, new_fragments|
            serialize_eadheader(data, xml, new_fragments)
          })

        atts = {:level => data.level, :otherlevel => data.other_level}
        atts.reject! {|k, v| v.nil?}

        xml.archdesc(atts) {

          xml.did {

            xml.head { xml.text "Descriptive Summary" }

            if (val = data.repo.name)
              xml.repository ( { 'encodinganalog' => '852$a' } ) {
                xml.corpname { sanitize_mixed_content(val, xml, @fragments) }
                if data.repo.url
                  xml.extref ( {
													 "xmlns:xlink" => "http://www.w3.org/1999/xlink",
                           "xlink:href" => data.repo.url,
                           "xlink:type" => "simple",
                           "xlink:show" => "new",
                           "xlink:actuate" => "onRequest" 
                           } )
                end
              }
            end

            if (val = data.title)
              xml.unittitle ( { 'encodinganalog' => '245$a' } ) {   sanitize_mixed_content(val, xml, @fragments) }
            end

            serialize_origination(data, xml, @fragments)

            unitid_atts = {:countrycode => data.repo.country,
              :repositorycode => data.mainagencycode,
              :encodinganalog => '099'}.reject {|k, v| v.nil? || v.empty? || v == "null" }
            unitid = (0..3).map {|i| data.send("id_#{i}")}.compact.join('.')
            xml.unitid(unitid_atts) { xml.text unitid }

#            if @include_unpublished
#              data.external_ids.each do |exid|
#                xml.unitid  ({ "audience" => "internal", "type" => exid['source'], "identifier" => exid['external_id']}) { xml.text exid['external_id']}
#              end
#            end

            if (languages = data.lang_materials)
              serialize_languages(languages, xml, @fragments)
            end

            serialize_extents(data, xml, @fragments)

            serialize_dates(data, xml, @fragments)

            serialize_did_notes(data, xml, @fragments)

            data.instances_with_sub_containers.each do |instance|
              serialize_container(instance, xml, @fragments)
            end

            EADSerializer.run_serialize_step(data, xml, @fragments, :did)

          }# </did>

          data.digital_objects.each do |dob|
            serialize_digital_object(dob, xml, @fragments)
          end

          serialize_nondid_notes(data, xml, @fragments)

          serialize_bibliographies(data, xml, @fragments)

          serialize_indexes(data, xml, @fragments)

          serialize_controlaccess(data, xml, @fragments)

          EADSerializer.run_serialize_step(data, xml, @fragments, :archdesc)

          dsc_attributes = { 'type' => 'combined' }
          xml.dsc(dsc_attributes) {

            data.children_indexes.each do |i|
              xml.text(
                       @stream_handler.buffer {|xml, new_fragments|
                         serialize_child(data.get_child(i), xml, new_fragments)
                       }
                       )
            end
          }
        }
      }

    rescue => e
      xml.text  "ASPACE EXPORT ERROR : YOU HAVE A PROBLEM WITH YOUR EXPORT OF YOUR RESOURCE. THE FOLLOWING INFORMATION MAY HELP:\n
                MESSAGE: #{e.message.inspect}  \n
                TRACE: #{e.backtrace.inspect} \n "
    end



    end
    doc.doc.root.add_namespace nil, 'urn:isbn:1-931666-22-9'

    Enumerator.new do |y|
      @stream_handler.stream_out(doc, @fragments, y)
    end
  end

  def serialize_aspace_uri(data, xml)
		#We don't want these
    #xml.unitid ({ 'type' => 'aspace_uri' }) { xml.text data.uri }
  end

	def serialize_child(data, xml, fragments, c_depth = 1)
    return if data["publish"] === false && !@include_unpublished
    return if data["suppressed"] === true

    tag_name = @use_numbered_c_tags ? :"c#{c_depth.to_s.rjust(2, '0')}" : :c

    atts = {:level => data.level, :otherlevel => data.other_level, :id => prefix_id(data.ref_id)}

    if data.publish === false
      atts[:audience] = 'internal'
    end

    atts.reject! {|k, v| v.nil?}
    xml.send(tag_name, atts) {

      xml.did {
        if (val = data.title)
          xml.unittitle { sanitize_mixed_content( val, xml, fragments) }
        end

        if !data.component_id.nil? && !data.component_id.empty?
          xml.unitid data.component_id
        end

        handle_arks(data, xml)

        serialize_aspace_uri(data, xml)

        if @include_unpublished
          data.external_ids.each do |exid|
            xml.unitid ({ "audience" => "internal", "type" => exid['source'], "identifier" => exid['external_id']}) { xml.text exid['external_id']}
          end
        end

        serialize_origination(data, xml, fragments)
        serialize_extents(data, xml, fragments)
        serialize_dates(data, xml, fragments)
        serialize_did_notes(data, xml, fragments)

        if (languages = data.lang_materials)
          serialize_languages(languages, xml, fragments)
        end

        EADSerializer.run_serialize_step(data, xml, fragments, :did)

        data.instances_with_sub_containers.each do |instance|
          serialize_container(instance, xml, @fragments)
        end

        if @include_daos
          data.instances_with_digital_objects.each do |instance|
            serialize_digital_object(instance['digital_object']['_resolved'], xml, fragments)
          end
        end
      }

      serialize_nondid_notes(data, xml, fragments)

      serialize_bibliographies(data, xml, fragments)

      serialize_indexes(data, xml, fragments)

      serialize_children_controlaccess(data, xml, fragments)

      EADSerializer.run_serialize_step(data, xml, fragments, :archdesc)

      data.children_indexes.each do |i|
        xml.text(
          @stream_handler.buffer {|xml, new_fragments|
            serialize_child(data.get_child(i), xml, new_fragments, c_depth + 1)
          }
        )
      end
    }
  end

  def serialize_origination(data, xml, fragments)
    unless data.creators_and_sources.nil?
      used_names = []
      data.creators_and_sources.each do |link|
        agent = link['_resolved']
        published = agent['publish'] === true

        next if !published && !@include_unpublished

        link['role'] == 'creator' ? role = link['role'].capitalize : role = link['role']
        relator = link['relator']
        sort_name = agent['display_name']['sort_name']
        next if used_names.include?(sort_name)
        used_names.push(sort_name)
        rules = agent['display_name']['rules']
        source = agent['display_name']['source']
        authfilenumber = agent['display_name']['authority_id']
        node_name = case agent['agent_type']
                    when 'agent_person'; 'persname'
                    when 'agent_family'; 'famname'
                    when 'agent_corporate_entity'; 'corpname'
                    when 'agent_software'; 'name'
                    end

        encodinganalog = case agent['agent_type']
                    when 'agent_person'; '100'
                    when 'agent_family'; '100'
                    when 'agent_corporate_entity'; '110'
                    when 'agent_software'; '130'
                    end

        origination_attrs = {:label => role}
        origination_attrs[:audience] = 'internal' unless published
        xml.origination(origination_attrs) {
          atts = {:role => relator, :source => source, :rules => rules, :authfilenumber => authfilenumber, :encodinganalog => encodinganalog}
          atts.reject! {|k, v| v.nil?}

          xml.send(node_name, atts) {
            sanitize_mixed_content(sort_name, xml, fragments )
            EADSerializer.run_serialize_step(agent, xml, fragments, node_name.to_sym)
          }
        }
      end
    end
  end

  def serialize_controlaccess(data, xml, fragments)
    if (data.controlaccess_subjects.length + data.controlaccess_linked_agents(@include_unpublished).reject {|x| x.empty?}.length) > 0
      xml.controlaccess {
        xml.head { xml.text "Index Terms" }
        if data.controlaccess_linked_agents(@include_unpublished).reject {|x| x.empty?}.length > 0
          agent_types = {"persname" => "Subjects (Persons)", "corpname" => "Subjects (Organizations)", "famname" => "Subjects (Families)"}
          agent_types.keys.each { |type| working_agents = data.controlaccess_linked_agents(@include_unpublished).zip(data.linked_agents).select{|node_data, agent| node_data[:node_name].to_s == type}
          if working_agents.length > 0
            xml.controlaccess { 
              xml.head { xml.text agent_types[type] }
              working_agents.each do |node_data, agent|
                xml.send(node_data[:node_name], node_data[:atts]) {
                  sanitize_mixed_content( node_data[:content], xml, fragments, ASpaceExport::Utils.include_p?(node_data[:node_name]) )
                  EADSerializer.run_serialize_step(agent['_resolved'], xml, fragments, node_data[:node_name].to_sym)
                }
              end
            }
          end
        	}
				end
        if data.controlaccess_subjects.length > 0
          subject_types = {"subject" => "Subjects", 
                          "geogname" => "Places", 
                          "genreform" => "Document Types",
                          "occupation" => "Occupations",
                          "function" => "Functions", 
                          "title" => "Uniform Titles"}
          subject_types.keys.each {|type| working_subjects = data.controlaccess_subjects.zip(data.subjects).select{ |node_data, subject| node_data[:node_name].to_s == type}
          if working_subjects.length > 0
            xml.controlaccess { 
              xml.head { xml.text subject_types[type] }
              working_subjects.each do |node_data, subject|
                xml.send(node_data[:node_name], node_data[:atts]) {
                  sanitize_mixed_content( node_data[:content], xml, fragments, ASpaceExport::Utils.include_p?(node_data[:node_name]) )
                  EADSerializer.run_serialize_step(subject['_resolved'], xml, fragments, node_data[:node_name].to_sym)
                }
              end
              }
          	end
          	}
					end
      } #</controlaccess>
    end
  end

  def serialize_children_controlaccess(data, xml, fragments)
    if (data.controlaccess_subjects.length + data.controlaccess_linked_agents(@include_unpublished).reject {|x| x.empty?}.length) > 0
      xml.controlaccess {
        if data.controlaccess_linked_agents(@include_unpublished).reject {|x| x.empty?}.length > 0
          agent_types = {"persname" => "Subjects (Persons)", "corpname" => "Subjects (Organizations)", "famname" => "Subjects (Families)"}
          agent_types.keys.each { |type| working_agents = data.controlaccess_linked_agents(@include_unpublished).zip(data.linked_agents).select{|node_data, agent| node_data[:node_name].to_s == type}
          if working_agents.length > 0
              working_agents.each do |node_data, agent|
                xml.send(node_data[:node_name], node_data[:atts]) {
                  sanitize_mixed_content( node_data[:content], xml, fragments, ASpaceExport::Utils.include_p?(node_data[:node_name]) )
                  EADSerializer.run_serialize_step(agent['_resolved'], xml, fragments, node_data[:node_name].to_sym)
                }
              end
          end
        	}
				end
        if data.controlaccess_subjects.length > 0
          subject_types = {"subject" => "Subjects", 
                          "geogname" => "Places", 
                          "genreform" => "Document Types",
                          "occupation" => "Occupations",
                          "function" => "Functions", 
                          "title" => "Uniform Titles"}
          subject_types.keys.each {|type| working_subjects = data.controlaccess_subjects.zip(data.subjects).select{ |node_data, subject| node_data[:node_name].to_s == type}
          if working_subjects.length > 0
              working_subjects.each do |node_data, subject|
                xml.send(node_data[:node_name], node_data[:atts]) {
                  sanitize_mixed_content( node_data[:content], xml, fragments, ASpaceExport::Utils.include_p?(node_data[:node_name]) )
                  EADSerializer.run_serialize_step(subject['_resolved'], xml, fragments, node_data[:node_name].to_sym)
                }
              end
          	end
          	}
					end
      } #</controlaccess>
    end
  end
  def serialize_digital_object(digital_object, xml, fragments)
    return if digital_object["publish"] === false && !@include_unpublished
    return if digital_object["suppressed"] === true

    # ANW-285: Only serialize file versions that are published, unless include_unpublished flag is set
    file_versions_to_display = digital_object['file_versions'].select {|fv| fv['publish'] == true || @include_unpublished }

    title = digital_object['title']
    date = digital_object['dates'][0] || {}
    atts = {}

    content = ""
    content << title if title
    content << ": " if date['expression'] || date['begin']
    if date['expression']
      content << date['expression']
    elsif date['begin']
      content << date['begin']
      if date['end'] != date['begin']
        content << "-#{date['end']}"
      end
    end
    atts['xlink:title'] = digital_object['title'] if digital_object['title']


    if file_versions_to_display.empty?
      atts['xlink:type'] = 'simple'
      atts['xlink:href'] = digital_object['digital_object_id']
      atts['xlink:actuate'] = 'onRequest'
      atts['xlink:show'] = 'new'
      atts['audience'] = 'internal' unless is_digital_object_published?(digital_object)
      xml.dao(atts) {
        xml.daodesc { sanitize_mixed_content(content, xml, fragments, true) } if content
      }
    elsif file_versions_to_display.length == 1
      file_version = file_versions_to_display.first

      atts['xlink:type'] = 'simple'
      atts['xlink:actuate'] = file_version['xlink_actuate_attribute'] || 'onRequest'
      atts['xlink:show'] = file_version['xlink_show_attribute'] || 'new'
      atts['xlink:role'] = if file_version['use_statement'] && digital_object['_is_in_representative_instance']
                             [file_version['use_statement'], 'representative'].join(' ')
                           elsif file_version['use_statement']
                             file_version['use_statement']
                           end
      atts['xlink:href'] = file_version['file_uri']
      xml.dao(atts) {
        xml.daodesc { sanitize_mixed_content(content, xml, fragments, true) } if content
      }
    else
      atts['xlink:type'] = 'extended'
      if digital_object['_is_in_representative_instance']
        atts['xlink:role'] = 'representative'
      end
      xml.daogrp( atts ) {
        xml.daodesc { sanitize_mixed_content(content, xml, fragments, true) } if content
        file_versions_to_display.each do |file_version|
          atts = {}
          atts['xlink:type'] = 'locator'
          atts['xlink:href'] = file_version['file_uri']
          atts['xlink:role'] = file_version['use_statement'] if file_version['use_statement']
          atts['xlink:title'] = file_version['caption'] if file_version['caption']
          xml.daoloc(atts)
        end
      }
    end
    EADSerializer.run_serialize_step(digital_object, xml, fragments, :dao)
  end

  def serialize_extents(obj, xml, fragments)
    if obj.extents.length
      obj.extents.each do |e|
        next if e["publish"] === false && !@include_unpublished
        audatt = e["publish"] === false ? {:audience => 'internal'} : {}
        xml.physdesc({:altrender => e['portion']}.merge(audatt), {:encodinganalog => '300$a'}) {
          if e['number'] && e['extent_type']
            xml.extent({:altrender => 'materialtype spaceoccupied'}) {
              sanitize_mixed_content("#{e['number']} #{I18n.t('enumerations.extent_extent_type.'+e['extent_type'], :default => e['extent_type'])}", xml, fragments)
            }
          end
          if e['container_summary']
            xml.extent({:altrender => 'carrier'}) {
              sanitize_mixed_content( e['container_summary'], xml, fragments)
            }
          end
          xml.physfacet { sanitize_mixed_content(e['physical_details'], xml, fragments) } if e['physical_details']
          xml.dimensions  { sanitize_mixed_content(e['dimensions'], xml, fragments) } if e['dimensions']
        }
      end
    end
  end

  def serialize_did_notes(data, xml, fragments)
    data.notes.each do |note|
      next if note["publish"] === false && !@include_unpublished
      next unless data.did_note_types.include?(note['type'])

      audatt = note["publish"] === false ? {:audience => 'internal'} : {}
      content = ASpaceExport::Utils.extract_note_text(note, @include_unpublished)

      att = { :id => prefix_id(note['persistent_id']) }.reject {|k, v| v.nil? || v.empty? || v == "null" }
      att ||= {}

      case note['type']
      when 'dimensions', 'physfacet'
        att[:label] = note['label'] if note['label']
        xml.physdesc(audatt, {:encodinganalog => '300$a'}) {
          xml.send(note['type'], att) {
            sanitize_mixed_content( content, xml, fragments, ASpaceExport::Utils.include_p?(note['type']) )
          }
        }
      when 'abstract'
        att[:label] = note['label'] if note['label']
        att[:encodinganalog] = '520$a'
        xml.send(note['type'], att.merge(audatt)) {
          sanitize_mixed_content(content, xml, fragments, ASpaceExport::Utils.include_p?(note['type']))
        }
      when 'physdesc', 'physloc'
        att[:label] = note['label'] if note['label']
        xml.send(note['type'], att.merge(audatt)) {
          sanitize_mixed_content(content, xml, fragments, ASpaceExport::Utils.include_p?(note['type']))
        }
      else
        xml.send(note['type'], att.merge(audatt)) {
          sanitize_mixed_content(content, xml, fragments, ASpaceExport::Utils.include_p?(note['type']))
        }
      end
    end
  end

  def serialize_languages(languages, xml, fragments)
    lm = []
    language_notes = languages.map {|l| l['notes']}.compact.reject {|e| e == [] }.flatten
    if !language_notes.empty?
      language_notes.each do |note|
        unless note["publish"] === false && !@include_unpublished
          audatt = note["publish"] === false ? {:audience => 'internal'} : {}
          content = ASpaceExport::Utils.extract_note_text(note, @include_unpublished)

          att = { :id => prefix_id(note['persistent_id']), :encodinganalog => '546$a' }.reject {|k, v| v.nil? || v.empty? || v == "null" }
          att ||= {}

          xml.send(note['type'], att.merge(audatt)) {
            sanitize_mixed_content(content, xml, fragments, ASpaceExport::Utils.include_p?(note['type']))
          }
          lm << note
        end
      end
      #if lm == []
      if 1
        languages = languages.map {|l| l['language_and_script']}.compact
        xml.langmaterial({:encodinganalog => '546$a'}) {
          languages.map {|language|
            punctuation = language.equal?(languages.last) ? '.' : ', '
            lang_translation = I18n.t("enumerations.language_iso639_2.#{language['language']}", :default => language['language'])
            if language['script']
              xml.language(:langcode => language['language'], :scriptcode => language['script']) {
                xml.text(lang_translation)
              }
            else
              xml.language(:langcode => language['language']) {
                xml.text(lang_translation)
              }
            end
            xml.text(punctuation)
          }
        }
      end
    # ANW-697: If no Language Text subrecords are available, the Language field translation values for each Language and Script subrecord should be exported, separated by commas, enclosed in <language> elements with associated @langcode and @scriptcode attribute values, and terminated by a period.
    else
      languages = languages.map {|l| l['language_and_script']}.compact
      if !languages.empty?
        xml.langmaterial({:encodinganalog => '546$a'}) {
          languages.map {|language|
            punctuation = language.equal?(languages.last) ? '.' : ', '
            lang_translation = I18n.t("enumerations.language_iso639_2.#{language['language']}", :default => language['language'])
            if language['script']
              xml.language(:langcode => language['language'], :scriptcode => language['script']) {
                xml.text(lang_translation)
              }
            else
              xml.language(:langcode => language['language']) {
                xml.text(lang_translation)
              }
            end
            xml.text(punctuation)
          }
        }
      end
    end
  end

  def serialize_note_content(note, xml, fragments)
    return if note["publish"] === false && !@include_unpublished
    audatt = note["publish"] === false ? {:audience => 'internal'} : {}
    content = note["content"]
    encodinganalogs =
      { "accessrestrict" => "506",
        "acqinfo" => "541",
        "altformavail" => "530",
        "bioghist" => "545",
        "custodhist" => "561",
        "langmaterial" => "546$a",
        "prefercite" => "524",
        "processinfo" => "583",
        "relatedmaterial" => "544 1",
        "scopecontent" => "520$b",
        "separatedmaterial" => "544 0",
        "userestrict" => "540"
      }
    
    encatt = encodinganalogs[note['type']].nil? ? {} : {:encodinganalog => encodinganalogs[note['type']] }
    atts = {:id => prefix_id(note['persistent_id']) }.reject {|k, v| v.nil? || v.empty? || v == "null" }.merge(audatt).merge(encatt)

    head_text = note['label'] ? note['label'] : I18n.t("enumerations._note_types.#{note['type']}", :default => note['type'])
    content, head_text = extract_head_text(content, head_text)
    xml.send(note['type'], atts) {
      xml.head { sanitize_mixed_content(head_text, xml, fragments) } unless ASpaceExport::Utils.headless_note?(note['type'], content )
      sanitize_mixed_content(content, xml, fragments, ASpaceExport::Utils.include_p?(note['type']) ) if content
      if note['subnotes']
        serialize_subnotes(note['subnotes'], xml, fragments, ASpaceExport::Utils.include_p?(note['type']))
      end
    }
  end

  def serialize_eadheader(data, xml, fragments)
    eadid_url = data.ead_location

    if AppConfig[:arks_enabled] && data.ark_name && (current_ark = data.ark_name.fetch('current', nil))
      eadid_url = current_ark
    end

    if @include_unpublished || data.is_finding_aid_status_published
      finding_aid_status = data.finding_aid_status
    else
      finding_aid_status = ""
    end

    eadheader_atts = {:findaidstatus => finding_aid_status,
                      :repositoryencoding => "iso15511",
                      :countryencoding => "iso3166-1",
                      :dateencoding => "iso8601",
                      :langencoding => "iso639-2b"}.reject {|k, v| v.nil? || v.empty? || v == "null"}

    xml.eadheader(eadheader_atts) {

      eadid_atts = {:countrycode => data.repo.country,
              :url => eadid_url,
              :mainagencycode => data.mainagencycode}.reject {|k, v| v.nil? || v.empty? || v == "null" }

      xml.eadid(eadid_atts) {
        xml.text data.ead_id
      }

      xml.filedesc {

        xml.titlestmt {

          titleproper = ""
          titleproper += "#{data.finding_aid_title} " if data.finding_aid_title
          titleproper += "#{data.title}" if ( data.title && titleproper.empty? )
          #titleproper += "<num>#{(0..3).map {|i| data.send("id_#{i}")}.compact.join('.')}</num>"
          xml.titleproper("type" => "filing") { sanitize_mixed_content(data.finding_aid_filing_title, xml, fragments)} unless data.finding_aid_filing_title.nil?
          xml.titleproper { sanitize_mixed_content(titleproper, xml, fragments) }
          xml.subtitle {  sanitize_mixed_content(data.finding_aid_subtitle, xml, fragments) } unless data.finding_aid_subtitle.nil?
          xml.author { sanitize_mixed_content(data.finding_aid_author, xml, fragments) }  unless data.finding_aid_author.nil?
          xml.sponsor("encodinganalog" => "536") { sanitize_mixed_content( data.finding_aid_sponsor, xml, fragments) } unless data.finding_aid_sponsor.nil?

        }

        unless data.finding_aid_edition_statement.nil?
          xml.editionstmt {
            sanitize_mixed_content(data.finding_aid_edition_statement, xml, fragments, true )
          }
        end

        xml.publicationstmt {
          xml.publisher { sanitize_mixed_content(data.repo.name, xml, fragments) }

          if data.repo.image_url
            xml.p ( { "id" => "logostmt" } ) {
                            xml.extref ({"xlink:href" => data.repo.image_url,
                                        "xlink:actuate" => "onLoad",
                                        "xlink:show" => "embed",
                                        "xlink:type" => "simple"
                                        })
                          }
          end
          if (data.finding_aid_date)
            xml.p {
                    val = data.finding_aid_date
                    xml.date { sanitize_mixed_content( val, xml, fragments) }
                  }
          end

          unless data.addresslines.empty?
            xml.address {
              data.addresslines.each do |line|
                xml.addressline { sanitize_mixed_content( line, xml, fragments) }
              end
              if data.repo.url
                xml.addressline ( "URL: " ) {
                   xml.extptr ( {
                           "xlink:href" => data.repo.url,
                           "xlink:title" => data.repo.url,
                           "xlink:type" => "simple",
                           "xlink:show" => "new"
                           } )
                 }
              end
            }
          end

          data.metadata_rights_declarations.each do |mrd|
            if mrd["license"]
              license_translation = I18n.t("enumerations.metadata_license.#{mrd['license']}", :default => mrd['license'])
              xml.p (license_translation)
            end
          end
        }

        if (data.finding_aid_series_statement)
          val = data.finding_aid_series_statement
          xml.seriesstmt {
            sanitize_mixed_content( val, xml, fragments, true )
          }
        end
        if ( data.finding_aid_note )
          val = data.finding_aid_note
          xml.notestmt { xml.note { sanitize_mixed_content( val, xml, fragments, true )} }
        end

      }

      xml.profiledesc {
        creation = "This finding aid was produced using ArchivesSpace on <date>#{Time.now}</date>."
        xml.creation { sanitize_mixed_content( creation, xml, fragments) }

        if (val = data.finding_aid_language_note)
          xml.langusage (fragments << val)
        else
          xml.langusage() {
            xml.text(I18n.t("resource.finding_aid_langusage_label"))
            xml.language({langcode: "#{data.finding_aid_language}", :scriptcode => "#{data.finding_aid_script}"}) {
              xml.text(I18n.t("enumerations.language_iso639_2.#{data.finding_aid_language}"))
              xml.text(", ")
              xml.text(I18n.t("enumerations.script_iso15924.#{data.finding_aid_script}"))
              xml.text(" #{I18n.t("language_and_script.script").downcase}")}
            xml.text(".")
          }
        end

        if (val = data.descrules)
          xml.descrules { sanitize_mixed_content(val, xml, fragments) }
        end
      }

      export_rs = @include_unpublished ? data.revision_statements : data.revision_statements.reject { |rs| !rs['publish'] }
      if export_rs.length > 0
        xml.revisiondesc {
          export_rs.each do |rs|
            if rs['description'] && rs['description'].strip.start_with?('<')
              xml.text (fragments << rs['description'] )
            else
              xml.change(rs['publish'] ? nil : {:audience => 'internal'}) {
                rev_date = rs['date'] ? rs['date'] : ""
                xml.date (fragments <<  rev_date )
                xml.item (fragments << rs['description']) if rs['description']
              }
            end
          end
        }
      end
    }
  end
end
