#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'sketchup.rb'
begin
  require 'TT_Lib2/core.rb'
rescue LoadError => e
  module TT
    if @lib2_update.nil?
      url = 'http://www.thomthom.net/software/sketchup/tt_lib2/errors/not-installed'
      options = {
        :dialog_title => 'TT_Lib² Not Installed',
        :scrollable => false, :resizable => false, :left => 200, :top => 200
      }
      w = UI::WebDialog.new( options )
      w.set_size( 500, 300 )
      w.set_url( "#{url}?plugin=#{File.basename( __FILE__ )}" )
      w.show
      @lib2_update = w
    end
  end
end


#-------------------------------------------------------------------------------

if defined?( TT::Lib ) && TT::Lib.compatible?( '2.7.0', 'Material Tools' )

module TT::Plugins::MaterialTools


  ### MENU & TOOLBARS ### ------------------------------------------------------

  unless file_loaded?( __FILE__ )
    m = TT.menu('Plugins').add_submenu('Material Tools')
    m.add_item('Instance Material to Faces')  { self.instance_materials_to_faces() }
    m.add_separator
    m.add_item('Remove From Entire Model')    { self.remove_all() }
    m.add_item('Remove From Selection')       { self.remove_all_from_selection() }
    m.add_item('Remove From All Edges')       { self.remove_edge_materials() }
    m.add_item('Remove From Faces and Edges') { self.remove_face_edge_materials() }
    m.add_item('Remove All Backface Materials') { self.remove_all_backface_materials() }
    m.add_item('Remove Specific Material')    { self.remove_spesific() }
    m.add_item('Remove All Textures')         { self.remove_textures() }
    m.add_separator
    m.add_item('List Textures in Console')    { self.list_textures() }
    m.add_item('Apply Colour Adjustments')    { self.apply_adjustments() }
    m.add_item('Ensure Unique Filenames')     { self.ensure_unique_texture_names() }
    m.add_separator
    m.add_item('Paint Roofs')                 { self.paint_selected_roofs() }
    m.add_separator
    m.add_item('Transparent Material to Backside') { self.transparent_to_backside() }
  end


  ### MAIN SCRIPT ### ----------------------------------------------------------


  ### Transparent Material to Backside #########################################


  def self.transparent_to_backside
    model = Sketchup.active_model

		TT::Model.start_operation( 'Transparent Material to Backside' )

		definitions = {}
		entities = model.selection.to_a
    entities = model.active_entities.to_a if entities.empty?

    size = TT::Entities.count_unique_entity( entities )
    progress = TT::Progressbar.new( size, 'Transparent Material to Backside' )

		until entities.empty?
      progress.next
			e = entities.shift
			if e.is_a?( Sketchup::Face )
				next unless e.material
        next unless e.material.alpha < 1.0
        e.back_material = e.material
			elsif TT::Instance.is?( e )
        definition = TT::Instance.definition( e )
        unless definitions[ definition ]
					entities += definition.entities.to_a
					definitions[ definition ] = definition
				end
			end
		end

		model.commit_operation
  end


  ### Paint Roofs ##############################################################


  def self.paint_selected_roofs
    model = Sketchup.active_model
    return if model.selection.empty?

    material = model.materials.current
    unless model.materials.include?( material )
      UI.messagebox( 'Select a material already in the model. Not from the libraries.' )
      return
    end

    TT::Model.start_operation( 'Paint Roofs' )
    self.paint_roofs( material, model.selection )
    model.commit_operation
  end

  def self.paint_roofs( material, entities )
    for e in entities
      if TT::Instance.is?( e )
        d = TT::Instance.definition( e )
        self.paint_roofs( material, d.entities )
      end
      next unless e.is_a?( Sketchup::Face )
      unless e.normal.perpendicular?( Z_AXIS )
        e.material = material
      end
    end
  end


  ### Remove All Textures ######################################################


  def self.remove_textures
    model = Sketchup.active_model
    TT::Model.start_operation('Remove All Textures')
    model.materials.each { |material|
      material.texture = nil
    }
    model.commit_operation
  end


  ### Instance Material to Faces ###############################################


  def self.instance_materials_to_faces
    model = Sketchup.active_model
    TT::Model.start_operation('Instance Material to Faces')
    self.instance_material_to_faces( model.selection, nil )
    model.commit_operation
  end

  def self.instance_material_to_faces( entities, material )
    for e in entities
      if TT::Instance.is?( e )
        temp_material = (e.material) ? e.material : material
        d = TT::Instance.definition( e )
        self.instance_material_to_faces( d.entities, temp_material )
        e.material = nil
      elsif e.is_a?( Sketchup::Face )
        e.material = material if e.material.nil?
        e.back_material = material if e.back_material.nil?
      end
    end
  end


  ### List Textures in Console #################################################


  GIGA_SIZE = 1073741824.0
  MEGA_SIZE = 1048576.0
  KILO_SIZE = 1024.0

  # Return the file size with a readable style.
  # http://www.ruby-forum.com/topic/126876
  def self.readable_file_size(size, precision)
    case
      when size == 1 then "1 Byte"
      when size < KILO_SIZE then "%d Bytes" % size
      when size < MEGA_SIZE then "%.#{precision}f KB" % (size / KILO_SIZE)
      when size < GIGA_SIZE then "%.#{precision}f MB" % (size / MEGA_SIZE)
      else "%.#{precision}f GB" % (size / GIGA_SIZE)
    end
  end

  def self.list_textures
    Sketchup.send_action('showRubyPanel:')
    # Collect textures and sort by size
    mats = Sketchup.active_model.materials.select { |m|
      !m.texture.nil?
    }
    mats.sort! { |a,b|
      size_a = a.texture.image_width * a.texture.image_height
      size_b = b.texture.image_width * b.texture.image_height
      size_b <=> size_a
    }
    # Print textures
    puts "=== TEXTURE MATERIALS BY SIZE ==="
    buffer = ''
    mats.each { |m|
      next if m.texture.nil?
      t = m.texture
      size = t.image_width * t.image_height
      file = File.basename( t.filename )
      path = File.dirname( t.filename )
      #puts "#{m.display_name} - #{t.image_width}x#{t.image_height} - #{t.filename}"
      buffer << "#{m.display_name}\n"
      buffer << "  Size: #{t.image_width}x#{t.image_height} pixels\n"
      buffer << "  Size: #{self.readable_file_size(size*3, 2)} estimated uncompressed RGB\n"
      buffer << "  Size: #{self.readable_file_size(size*4, 2)} estimated uncompressed RGBA\n"
      if File.exist?( t.filename )
        disksize = File.size( t.filename )
        buffer << "  Size: #{self.readable_file_size(disksize, 2)} on disk\n"
      end
      buffer << "  File: #{file}\n"
      buffer << "  Path: #{path}\n"
    }
    puts buffer
    puts "---"
  end


  ### Apply Colour Adjustments #################################################


  # Applies the colour adjustments for colourized/adjusted textures and bakes
  # them into a texture file.
  def self.apply_adjustments
    tmp_path = self.clean_temp_path

    TT::Model.start_operation('Apply Material Colour Adjustments')
    puts '=== APPLY MATERIAL COLOUR ADJUSTMENTS ==='
    model = Sketchup.active_model
    # Find all adjusted textures
    materials = model.materials.select { |m| m.materialType == 2 }
    # Make temp groups/edges for each material and apply
    tw = Sketchup.create_texture_writer
    g = model.entities.add_group
    # Cache used filenames to ensure unique names
    used_filenames = []
    begin
      materials.each { |m|
        ext = File.extname( m.texture.filename )
        basename = File.basename( m.texture.filename, ext )
        filename = "#{basename}#{ext}"
        # Ensure unique name. Filename + Number. Increase
        # number until filename is unique
        if used_filenames.include?( filename )
          match = basename.match( /(.+)(\d)$/ )
          if match.nil?
            base = basename
            copy = '0'
          else
            base = match[1]
            copy = match[2]
          end
          while used_filenames.include?( filename = "#{base}#{copy}#{ext}" )
            copy.next!
          end
        end
        used_filenames << filename
        #
        file = File.join( tmp_path, filename )
        puts "Processing #{filename} ..."
        g.material = m
        # Save to disk (this bakes it into a texture file)
        # (!) Generate unique name
        tw.load( g )
        result = tw.write( g, file )
        puts "> Write: #{result} ..."
        next unless result == FILE_WRITE_OK
        # Reload texture (ensure to reset old adjustments)
        width  = m.texture.width
        height = m.texture.height
        m.texture = file
        m.texture.size = [width, height]
        puts '> Read OK...'
        # Cleanup
        result = File.delete( file )
        result=nil ##
        puts "> Cleanup: #{result}"
      }
    rescue => error
      puts '> Unexpected error!'
      p error.message
      p error.backtrace
    ensure
      g.erase!
    end
    model.commit_operation
    puts "Done! #{materials.size} materials processed."
  end


  ### Ensure Unique Filenames ##################################################


  def self.is_ascii?( string )
    string.each_byte { |byte|
      return false if byte > 127
    }
    return true
  end


  # Ensure unique texture filenames for broken file references..
  def self.ensure_unique_texture_names
    tmp_path = self.clean_temp_path

    TT::Model.start_operation('Ensure Unique Texture Filenames')
    puts '=== ENSURE UNIQUE TEXTURE FILENAMES ==='
    model = Sketchup.active_model
    # Find all adjusted textures
    materials = model.materials.select { |m|
      m.materialType > 0 &&
      self.is_ascii?( m.texture.filename ) &&
      !File.exists?( m.texture.filename )
    }
    ##materials.each { |m| puts "#{m.name} - #{m.texture.filename}" }
    # Make temp groups/edges for each material and apply
    tw = Sketchup.create_texture_writer
    g = model.entities.add_group
    # Cache used filenames to ensure unique names
    used_filenames = []
    begin
      materials.each { |m|
        ext = File.extname( m.texture.filename )
        basename = File.basename( m.texture.filename, ext )
        filename = "#{basename}#{ext}"

        # If the filename was not in the list already there is no need to
        # rename.
        unless used_filenames.include?( filename )
          puts "> Skipping #{filename}..."
          used_filenames << filename
          next
        end

        # Ensure unique name. Filename + Number. Increase
        # number until filename is unique
        match = basename.match( /(.+)(\d)$/ )
        if match.nil?
          base = basename
          copy = '0'
        else
          base = match[1]
          copy = match[2]
        end
        while used_filenames.include?( filename = "#{base}#{copy}#{ext}" )
          copy.next!
        end

        used_filenames << filename

        # Write out texture to temp path with new file and load back into
        # the material.
        puts "> Rename #{m.texture.filename} to #{filename}"
        file = File.join( tmp_path, "#{filename}" )
        g.material = m
        # Save to disk
        tw.load( g )
        result = tw.write( g, file )
        puts ">>> Write: #{result}"
        next if result != FILE_WRITE_OK
        # Reload texture (ensure to reset old adjustments)
        width  = m.texture.width
        height = m.texture.height
        m.texture = file
        m.texture.size = [width, height]
        puts '>>> Read OK'
        # Cleanup
        result = File.delete( file )
        puts ">>> Cleanup: #{result}"
      }
      #puts used_filenames.join("\n")
    rescue => error
      puts '> Unexpected error!'
      p error.message
      p error.backtrace
    ensure
      g.erase!
    end
    model.commit_operation
    puts "Done! #{materials.size} materials processed."
  end


  ### Remove Specific Material #################################################


  # Specific From Selection
  def self.remove_spesific
    model = Sketchup.active_model
    sel = model.selection
    definitions = []

    # Prompt for material to remove
    materials = model.materials.map { |m| m.name }.join('|')

    prompts = ['What material to remove?']
    defaults = ['Enter name']

    result = UI.inputbox(prompts, defaults, [materials], 'Remove material.')
    return if result == false

    material = model.materials[ result[0] ]

    TT::Model.start_operation('Remove Material')

    sel.each { |e|
      if TT::Instance.is?( e )
        parent = TT::Instance.definition( e )
        next if definitions.include?(parent)
        parent.entities.each { |ents|
          ents.material = nil if ents.material == material
          if ents.respond_to?( :back_material )
            ents.back_material = nil if ents.back_material == material
          end
        }
        definitions << parent
      elsif e.respond_to?( :material )
        e.material = nil if e.material == material
        if ents.respond_to?( :back_material )
          e.back_material = nil if e.back_material == material
        end
      end
    }

    model.commit_operation
  end


  ### Remove From Selection ####################################################


  # Remove From Selection
  def self.remove_all_from_selection
    # Variables
    model = Sketchup.active_model
    TT::Model.start_operation('Remove Selection Material')
    self.remove_material( model.selection )
    model.commit_operation
  end


  def self.remove_material( entities, processed_definitions = [] )
    for e in entities
      e.material = nil if e.respond_to?( :material )
      e.back_material = nil if e.respond_to?( :back_material )
      if TT::Instance.is?( e )
        definition = TT::Instance.definition( e )
        next if processed_definitions.include?( definition )
        processed_definitions << definition
        self.remove_material( definition.entities, processed_definitions )
      end
    end
  end


  ### Remove From Entire Model #################################################


  # Remove From Entire Model
  def self.remove_all
    model = Sketchup.active_model
    TT::Model.start_operation('Remove All Materials')
    model.entities.each { |e|
      e.material = nil if e.respond_to?( :material )
      e.back_material = nil if e.respond_to?( :back_material )
    }
    model.definitions.each { |d|
      next if d.image?
      d.entities.each { |e|
        e.material = nil if e.respond_to?( :material )
        e.back_material = nil if e.respond_to?( :back_material )
      }
    }
    model.commit_operation
  end


  ### Remove From All Edges ####################################################


  # Remove From All Edges
  def self.remove_edge_materials
    model = Sketchup.active_model
    TT::Model.start_operation('Remove Edge Materials')
    model.entities.each { |e|
      e.material = nil if e.kind_of?(Sketchup::Edge)
    }
    model.definitions.each { |d|
      next if d.image?
      d.entities.each { |e|
        e.material = nil if e.kind_of?(Sketchup::Edge)
      }
    }
    model.commit_operation
  end


  ### Remove From Faces and Edges ##############################################


  # Remove Faces and Edges
  def self.remove_face_edge_materials
    TT::Model.start_operation('Keep only C/G materials')
    self.remove_materials(Sketchup.active_model.entities)
    Sketchup.active_model.definitions.each { |d|
      next if d.image?
      self.remove_materials(d.entities)
    }
    Sketchup.active_model.commit_operation
  end

  def self.remove_materials(entities)
    entities.each { |e|
      next if TT::Instance.is?( e )
      e.material = nil if e.respond_to?( :material )
      e.back_material = nil if e.respond_to?( :back_material )
    }
  end


  ### Remove All Backface Materials ############################################


  def self.remove_backface_materials(entities)
    entities.each { |e|
      e.back_material = nil if e.respond_to?( :back_material )
    }
  end

  def self.remove_all_backface_materials
    TT::Model.start_operation('Remove Backface Materials')
    self.remove_backface_materials(Sketchup.active_model.entities)
    Sketchup.active_model.definitions.each { |d|
      next if d.image?
      self.remove_backface_materials(d.entities)
    }
    Sketchup.active_model.commit_operation
  end


  ### Generic ##################################################################

  # @since 2.7.0
  # @return [String] temp path
  def self.clean_temp_path
    path = File.join( TT::System.temp_path, PLUGIN_ID )
    Dir.mkdir( path ) unless File.exists?( path )
    Dir.glob( File.join( path, '*') ).each { |filename|
      p filename
      p File.delete( filename )
    }
    path
  end


  ### DEBUG ### ----------------------------------------------------------------

  # @note Debug method to reload the plugin.
  #
  # @example
  #   TT::Plugins::MaterialTools.reload
  #
  # @param [Boolean] tt_lib Reloads TT_Lib2 if +true+.
  #
  # @return [Integer] Number of files reloaded.
  # @since 1.0.0
  def self.reload( tt_lib = false )
    original_verbose = $VERBOSE
    $VERBOSE = nil
    TT::Lib.reload if tt_lib
    # Core file (this)
    load __FILE__
    # Supporting files
    if defined?( PATH ) && File.exist?( PATH )
      x = Dir.glob( File.join(PATH, '*.{rb,rbs}') ).each { |file|
        load file
      }
      x.length + 1
    else
      1
    end
  ensure
    $VERBOSE = original_verbose
  end

end # module


end # if TT_Lib

#-------------------------------------------------------------------------------

file_loaded( __FILE__ )

#-------------------------------------------------------------------------------