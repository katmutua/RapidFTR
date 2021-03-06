require 'spec_helper'

describe BaseModel, :type => :model do
  describe 'photo attachments' do

    before(:each) do
      allow(Clock).to receive(:now).and_return(Time.parse('Jan 20 2010 17:10:32'))
    end

    context 'with no photos' do
      it 'should have an empty set' do
        expect(BaseModel.new.photos).to be_empty
      end

      it 'should not have a primary photo' do
        expect(BaseModel.new.primary_photo).to be_nil
      end
    end

    context 'with a single new photo' do
      before :each do
        allow(User).to receive(:find_by_user_name).and_return(double(:organisation => 'stc'))
        @base_model = BaseModel.create('photo' => uploadable_photo, 'last_known_location' => 'London', 'created_by' => 'me', 'created_organisation' => 'stc')
      end

      it 'should only have one photo on creation' do
        expect(@base_model.photos.size).to eql 1
      end

      it 'should be the primary photo' do
        expect(@base_model.primary_photo).to match_photo uploadable_photo
      end

    end

    context 'with multiple new photos' do
      before :each do
        allow(User).to receive(:find_by_user_name).and_return(double(:organisation => 'stc'))
        @base_model = BaseModel.create('photo' => {'0' => uploadable_photo_jeff, '1' => uploadable_photo_jorge}, 'last_known_location' => 'London', 'created_by' => 'me')
      end

      it 'should have corrent number of photos after creation' do
        expect(@base_model.photos.size).to eql 2
      end

      it 'should order by primary photo' do
        @base_model.primary_photo_id = @base_model['photo_keys'].last
        expect(@base_model.photos.first.name).to eq(@base_model['current_photo_key'])
      end

      it 'should return the first photo as a primary photo' do
        expect(@base_model.primary_photo).to match_photo uploadable_photo_jeff
      end

      it 'should not allow duplicate photos' do
        photos = {'0' => uploadable_photo_jeff, '1' => uploadable_photo_jeff}
        base_model = BaseModel.create('photo' => photos, 'last_known_location' => 'London', 'created_by' => 'me')
        expect(base_model.photos.size).to eq 1
      end
    end

    context 'when rotating an existing photo' do
      before :each do
        allow(User).to receive(:find_by_user_name).and_return(double(:organisation => 'stc'))
        @base_model = BaseModel.create('photo' => uploadable_photo, 'last_known_location' => 'London', 'created_by' => 'me', 'created_organisation' => 'stc')
        allow(Clock).to receive(:now).and_return(Time.parse('Feb 20 2010 12:04:32'))
      end

      it 'should become the primary photo' do
        existing_photo = @base_model.primary_photo
        @base_model.rotate_photo(180)
        @base_model.save
        # TODO: should be a better way to check rotation other than stubbing Minimagic ?
        expect(@base_model.primary_photo).not_to match_photo existing_photo
      end

      it 'should delete the original orientation' do
        existing_photo = @base_model.primary_photo
        @base_model.rotate_photo(180)
        @base_model.save
        expect(@base_model.primary_photo.name).to eql existing_photo.name
        expect(existing_photo).not_to match_photo @base_model.primary_photo
        expect(@base_model.photos.size).to eql 1
      end
    end
  end

  describe 'photo logging' do

    before :each do
      allow(Clock).to receive(:now).and_return(Time.parse('Jan 20 2010 12:04:24'))
      allow(User).to receive(:find_by_user_name).and_return(double(:organisation => 'stc'))
      @base_model = BaseModel.create('photo' => uploadable_photo, 'last_known_location' => 'London', 'created_by' => 'me', 'created_organisation' => 'stc')
      allow(Clock).to receive(:now).and_return(Time.parse('Feb 20 2010 12:04:24'))
    end

    it 'should log new photo key on adding a photo' do
      @base_model.photo = uploadable_photo_jeff
      @base_model.save
      changes = @base_model['histories'].first['changes']
      # TODO: this should be instead base_model.photo_history.first.to or something like that
      expect(changes['photo_keys']['added'].first).to match(/photo.*?-2010-02-20T120424/)
    end

    it 'should log multiple photos being added' do
      @base_model.photos = [uploadable_photo_jeff, uploadable_photo_jorge]
      @base_model.save
      changes = @base_model['histories'].first['changes']
      expect(changes['photo_keys']['added'].size).to eq(2)
      expect(changes['photo_keys']['deleted']).to be_nil
    end

    it 'should log a photo being deleted' do
      @base_model.photos = [uploadable_photo_jeff, uploadable_photo_jorge]
      @base_model.save
      @base_model.delete_photos([@base_model.photos.first.name])
      @base_model.save
      changes = @base_model['histories'][0]['changes']
      expect(changes['photo_keys']['deleted'].size).to eq(1)
      expect(changes['photo_keys']['added']).to be_nil
    end

    it 'should take the current photo key during base_model creation and update it appropriately with the correct format' do
      @base_model = BaseModel.create('photo' => {'0' => uploadable_photo, '1' => uploadable_photo_jeff}, 'last_known_location' => 'London', 'current_photo_key' => uploadable_photo_jeff.original_filename, 'created_by' => 'me', 'created_organisation' => 'stc')
      @base_model.save
      expect(@base_model.primary_photo.name).to eq(@base_model.photos.first.name)
      expect(@base_model.primary_photo.name).to start_with('photo-')
    end

    it 'should not log anything if no photo changes have been made' do
      @base_model['last_known_location'] = 'Moscow'
      @base_model.save
      changes = @base_model['histories'].first['changes']
      expect(changes['photo_keys']).to be_nil
    end

    it 'should select a new primary photo if the current one is deleted' do
      @base_model.photos = [uploadable_photo_jeff]
      @base_model.save
      original_primary_photo_key = @base_model.photos[0].name
      jeff_photo_key = @base_model.photos[1].name
      expect(@base_model.primary_photo.name).to eq(original_primary_photo_key)
      @base_model.delete_photos([original_primary_photo_key])
      @base_model.save
      expect(@base_model.primary_photo.name).to eq(jeff_photo_key)
    end

    it 'should delete items like _328 and _160x160 in attachments' do
      base_model = BaseModel.new
      base_model.photo = uploadable_photo
      base_model.save

      photo_key = base_model.photos[0].name
      uploadable_photo_328 = FileAttachment.new(photo_key + '_328', 'image/jpg', 'data')
      uploadable_photo_160x160 = FileAttachment.new(photo_key + '_160x160', 'image/jpg', 'data')
      base_model.attach(uploadable_photo_328)
      base_model.attach(uploadable_photo_160x160)
      base_model.save
      expect(base_model[:_attachments].keys.size).to eq(3)

      base_model.delete_photos [base_model.primary_photo.name]
      base_model.save
      expect(base_model[:_attachments].keys.size).to eq(0)
    end
  end

  describe 'photo validation' do
    it 'should disallow file formats that are not photo formats' do
      base_model = BaseModel.new
      base_model.photo = uploadable_photo_gif
      expect(base_model).not_to be_valid
      base_model.photo = uploadable_photo_bmp
      expect(base_model).not_to be_valid
    end

    it 'should disallow image file formats that are not png or jpg' do
      base_model = BaseModel.new
      base_model.photo = uploadable_photo
      expect(base_model).to be_valid
      base_model.photo = uploadable_text_file
      expect(base_model).not_to be_valid
    end

    it 'should disallow a photo larger than 10 megabytes' do
      photo = uploadable_large_photo
      base_model = BaseModel.new
      base_model.photo = photo
      expect(base_model).not_to be_valid
    end

    it 'should not save with image file formats that are not png or jpg' do
      photo = uploadable_photo
      base_model = BaseModel.new('created_by' => 'me', 'created_organisation' => 'stc')
      base_model.photo = photo
      expect(base_model.save.present?).to eq(true)
      loaded_base_model = BaseModel.get(base_model.id)
      expect(loaded_base_model.save.present?).to eq(true)
      loaded_base_model.photo = uploadable_text_file
      expect(loaded_base_model.save).to eq(false)
    end

    it 'should not save file formats that are not photo formats' do
      base_model = BaseModel.new
      base_model.photo = uploadable_photo_gif
      expect(base_model.save).to eq(false)
      base_model.photo = uploadable_photo_bmp
      expect(base_model.save).to eq(false)
    end

    it 'should save file based on content type' do
      base_model = BaseModel.new('created_by' => 'me', 'created_organisation' => 'stc')
      photo = uploadable_jpg_photo_without_file_extension
      base_model[:photo] = photo
      expect(base_model.save.present?).to eq(true)
    end
  end

  describe 'audio' do
    before(:each) do
      @base_model = BaseModel.new
      allow(@base_model).to receive(:attach)
      @file_attachment = mock_model(FileAttachment, :data => 'My Data', :name => 'some name', :mime_type => Mime::Type.lookup('audio/mpeg'))
    end

    it "should create an 'original' key in the audio hash" do
      @base_model.audio = uploadable_audio
      expect(@base_model['audio_attachments']).to have_key('original')
    end

    it "should create a FileAttachment with uploaded file and prefix 'audio'" do
      uploaded_file = uploadable_audio
      expect(FileAttachment).to receive(:from_uploadable_file).with(uploaded_file, 'audio').and_return(@file_attachment)
      @base_model.audio = uploaded_file
    end

    it "should store the audio attachment key with the 'original' key in the audio hash" do
      allow(FileAttachment).to receive(:from_uploadable_file).and_return(@file_attachment)
      @base_model.audio = uploadable_audio
      expect(@base_model['audio_attachments']['original']).to eq('some name')
    end

    it "should store the audio attachment key with the 'mime-type' key in the audio hash" do
      allow(FileAttachment).to receive(:from_uploadable_file).and_return(@file_attachment)
      @base_model.audio = uploadable_audio
      expect(@base_model['audio_attachments']['mp3']).to eq('some name')
    end

  end

  describe '.add_audio_file' do
    before :each do
      @file = double('File')
      allow(File).to receive(:binread).with(@file).and_return('ABC')
      @file_attachment = FileAttachment.new('attachment_file_name', 'audio/mpeg', 'data')
    end

    it 'should use Mime::Type.lookup to create file name postfix' do
      base_model = BaseModel.new
      expect(Mime::Type).to receive(:lookup).exactly(2).times.with('audio/mpeg').and_return('abc'.to_sym)
      base_model.add_audio_file(@file, 'audio/mpeg')
    end

    it "should create a file attachment for the file with 'audio' prefix, mime mediatype as postfix" do
      base_model = BaseModel.new
      allow(Mime::Type).to receive(:lookup).and_return('abc'.to_sym)
      expect(FileAttachment).to receive(:from_file).with(@file, 'audio/mpeg', 'audio', 'abc').and_return(@file_attachment)
      base_model.add_audio_file(@file, 'audio/mpeg')
    end

    it "should add attachments key attachment to the audio hash using the content's media type as key" do
      base_model = BaseModel.new
      allow(FileAttachment).to receive(:from_file).and_return(@file_attachment)
      base_model.add_audio_file(@file, 'audio/mpeg')
      expect(base_model['audio_attachments']['mp3']).to eq('attachment_file_name')
    end
  end

  describe '.audio' do

    before :each do
      allow(User).to receive(:find_by_user_name).and_return(double(:organisation => 'stc'))
    end

    it 'should return nil if no audio file has been set' do
      base_model = BaseModel.new
      expect(base_model.audio).to be_nil
    end

    it "should check if 'original' audio attachment is present" do
      base_model = BaseModel.create('audio' => uploadable_audio, 'created_by' => 'me', 'created_organisation' => 'stc')
      base_model['audio_attachments']['original'] = 'ThisIsNotAnAttachmentName'
      expect(base_model).to receive(:has_attachment?).with('ThisIsNotAnAttachmentName').and_return(false)
      base_model.audio
    end

    it 'should return nil if the recorded audio key is not an attachment' do
      base_model = BaseModel.create('audio' => uploadable_audio, 'created_by' => 'me', 'created_organisation' => 'stc')
      base_model['audio_attachments']['original'] = 'ThisIsNotAnAttachmentName'
      expect(base_model.audio).to be_nil
    end

    it 'should retrieve attachment data for attachment key' do
      allow(Clock).to receive(:now).and_return(Time.parse('Feb 20 2010 12:04:32'))
      base_model = BaseModel.create('audio' => uploadable_audio, 'created_by' => 'me', 'created_organisation' => 'stc')
      expect(base_model).to receive(:read_attachment).with('audio-2010-02-20T120432').and_return('Some audio')
      base_model.audio
    end

    it 'should create a FileAttachment with the read attachment and the attachments content type' do
      allow(Clock).to receive(:now).and_return(Time.parse('Feb 20 2010 12:04:32'))
      uploaded_amr = uploadable_audio_amr
      base_model = BaseModel.create('audio' => uploaded_amr, 'created_by' => 'me', 'created_organisation' => 'stc')
      expected_data = 'LA! LA! LA! Audio Data'
      allow(base_model).to receive(:read_attachment).and_return(expected_data)
      expect(FileAttachment).to receive(:new).with('audio-2010-02-20T120432', uploaded_amr.content_type, expected_data)
      base_model.audio
    end

    it 'should return nil if base_model has not been saved' do
      base_model = BaseModel.new('audio' => uploadable_audio, 'created_by' => 'me', 'created_organisation' => 'stc')
      expect(base_model.audio).to be_nil
    end
  end

  describe 'audio attachment' do
    before :each do
      allow(User).to receive(:find_by_user_name).and_return(double(:organisation => 'stc'))
    end

    it 'should create a field with recorded_audio on creation' do
      allow(Clock).to receive(:now).and_return(Time.parse('Jan 20 2010 17:10:32'))
      base_model = BaseModel.create('photo' => uploadable_photo, 'last_known_location' => 'London', 'audio' => uploadable_audio, 'created_by' => 'me', 'created_organisation' => 'stc')

      expect(base_model['audio_attachments']['original']).to eq('audio-2010-01-20T171032')
    end

    it 'should change audio file if a new audio file is set' do
      base_model = BaseModel.create('photo' => uploadable_photo, 'last_known_location' => 'London', 'audio' => uploadable_audio, 'created_by' => 'me', 'created_organisation' => 'stc')
      allow(Clock).to receive(:now).and_return(Time.parse('Feb 20 2010 12:04:32'))
      base_model.update_attributes :audio => uploadable_audio
      expect(base_model['audio_attachments']['original']).to eq('audio-2010-02-20T120432')
    end

    describe 'audio validation' do
      it 'should disllow an audio file larger than 10 megabytes' do
        base_model = BaseModel.new
        base_model.audio = uploadable_large_audio
        expect(base_model).not_to be_valid
      end

      it 'should not save with an audio file larger than 10 megabytes' do
        base_model = BaseModel.new('created_by' => 'me', 'created_organisation' => 'stc')
        base_model.audio = uploadable_large_audio
        expect(base_model.save).to eq(false)
      end

      it 'should disallow file formats that are not supported audio formats' do
        base_model = BaseModel.new
        base_model.audio = uploadable_photo_gif
        expect(base_model).not_to be_valid
        base_model.audio = uploadable_audio_amr
        expect(base_model).to be_valid
        base_model.audio = uploadable_audio_mp3
        expect(base_model).to be_valid
        base_model.audio = uploadable_audio_wav
        expect(base_model).not_to be_valid
        base_model.audio = uploadable_audio_ogg
        expect(base_model).not_to be_valid
      end

      it 'should not save with file formats that are not supported audio formats' do
        base_model = BaseModel.new('created_by' => 'me', 'created_organisation' => 'stc')
        base_model.audio = uploadable_photo_gif
        expect(base_model.save).to eq(false)
        base_model.audio = uploadable_audio_amr
        expect(base_model.save.present?).to eq(true)
        base_model.audio = uploadable_audio_mp3
        expect(base_model.save.present?).to eq(true)
        base_model.audio = uploadable_audio_wav
        expect(base_model.save).to eq(false)
        base_model.audio = uploadable_audio_ogg
        expect(base_model.save).to eq(false)
      end
    end
  end

  describe 'history log' do
    let(:mock_user) { double(:organisation => 'UNICEF', :user_name => 'some_user') }

    before do
      fields = [
        build(:text_field, :name => 'last_known_location'),
        build(:text_field, :name => 'age'),
        build(:text_field, :name => 'origin'),
        build(:radio_button_field, :name => 'gender', :option_strings => %w(male female)),
        build(:photo_field, :name => 'current_photo_key'),
        build(:audio_field, :name => 'recorded_audio')
      ]
      allow(FormSection).to receive(:all_visible_child_fields_for_form).and_return(fields)
    end

    before :each do
      allow(User).to receive(:find_by_user_name).with(anything).and_return(mock_user)
      User.current_user = mock_user
    end

    after :each do
      User.current_user = nil
    end

    it 'should update history with current_user for last_updated_by' do
      base_model = BaseModel.create('photo' => uploadable_photo, 'last_known_location' => 'London', 'created_by' => 'me', 'created_organisation' => 'stc')
      base_model['last_known_location'] = 'Philadelphia'
      base_model.save!
      expect(base_model['histories'].first['user_name']).to eq('some_user')
      expect(base_model['histories'].first['user_organisation']).to eq('UNICEF')
    end

    it 'should add a history entry when a record is created' do
      base_model = BaseModel.create('last_known_location' => 'New York', 'created_by' => 'me')
      expect(base_model['histories'].size).to be 1
      expect(base_model['histories'][0]).to eq('changes' => {'basemodel' => {:created => nil}}, 'datetime' => nil, 'user_name' => 'me', 'user_organisation' => 'UNICEF')
    end

    it "should update history with 'from' value on last_known_location update" do
      base_model = BaseModel.create('last_known_location' => 'New York', 'photo' => uploadable_photo, 'created_by' => 'me')
      base_model['last_known_location'] = 'Philadelphia'
      base_model.save!
      changes = base_model['histories'].first['changes']
      expect(changes['last_known_location']['from']).to eq('New York')
    end

    it "should update history with 'to' value on last_known_location update" do
      base_model = BaseModel.create('last_known_location' => 'New York', 'photo' => uploadable_photo, 'created_by' => 'me')
      base_model['last_known_location'] = 'Philadelphia'
      base_model.save!
      changes = base_model['histories'].first['changes']
      expect(changes['last_known_location']['to']).to eq('Philadelphia')
    end

    it "should update history with 'from' value on age update" do
      base_model = BaseModel.create('age' => '8', 'last_known_location' => 'New York', 'photo' => uploadable_photo, 'created_by' => 'me')
      base_model['age'] = '6'
      base_model.save!
      changes = base_model['histories'].first['changes']
      expect(changes['age']['from']).to eq('8')
    end

    it "should update history with 'to' value on age update" do
      base_model = BaseModel.create('age' => '8', 'last_known_location' => 'New York', 'photo' => uploadable_photo, 'created_by' => 'me')
      base_model['age'] = '6'
      base_model.save!
      changes = base_model['histories'].first['changes']
      expect(changes['age']['to']).to eq('6')
    end

    it 'should update history with a combined history record when multiple fields are updated' do
      base_model = BaseModel.create('age' => '8', 'last_known_location' => 'New York', 'photo' => uploadable_photo, 'created_by' => 'me')
      base_model['age'] = '6'
      base_model['last_known_location'] = 'Philadelphia'
      base_model.save!
      expect(base_model['histories'].size).to eq(2)
      changes = base_model['histories'].first['changes']
      expect(changes['age']['from']).to eq('8')
      expect(changes['age']['to']).to eq('6')
      expect(changes['last_known_location']['from']).to eq('New York')
      expect(changes['last_known_location']['to']).to eq('Philadelphia')
    end

    it 'should not record anything in the history if a save occured with no changes' do
      base_model = BaseModel.create('photo' => uploadable_photo, 'last_known_location' => 'New York', 'created_by' => 'me', 'created_organisation' => 'stc')
      base_model.save!
      expect(base_model['histories'].size).to be 1
    end

    it 'should not record empty string in the history if only change was spaces' do
      base_model = BaseModel.create('origin' => '', 'photo' => uploadable_photo, 'last_known_location' => 'New York', 'created_by' => 'me', 'created_organisation' => 'stc')
      base_model['origin'] = '    '
      base_model.save!
      expect(base_model['histories'].size).to be 1
    end

    it 'should not record history on populated field if only change was spaces' do
      base_model = BaseModel.create('last_known_location' => 'New York', 'photo' => uploadable_photo, 'created_by' => 'me', 'created_organisation' => 'stc')
      base_model['last_known_location'] = ' New York   '
      base_model.save!
      expect(base_model['histories'].size).to be 1
    end

    it 'should record history for newly populated field that previously was null' do
      # gender is the only field right now that is allowed to be nil when creating base_model document
      base_model = BaseModel.create('gender' => nil, 'last_known_location' => 'London', 'photo' => uploadable_photo, 'created_by' => 'me', 'created_organisation' => 'stc')
      base_model['gender'] = 'Male'
      base_model.save!
      expect(base_model['histories'].first['changes']['gender']['from']).to be_nil
      expect(base_model['histories'].first['changes']['gender']['to']).to eq('Male')
    end

    it 'should apend latest history to the front of histories' do
      base_model = BaseModel.create('last_known_location' => 'London', 'photo' => uploadable_photo, 'created_by' => 'me', 'created_organisation' => 'stc')
      base_model['last_known_location'] = 'New York'
      base_model.save!
      base_model['last_known_location'] = 'Philadelphia'
      base_model.save!
      expect(base_model['histories'].size).to eq(3)
      expect(base_model['histories'][0]['changes']['last_known_location']['to']).to eq('Philadelphia')
      expect(base_model['histories'][1]['changes']['last_known_location']['to']).to eq('New York')
    end

    it 'should update history with the datetime' do
      base_model = BaseModel.create('photo' => uploadable_photo, 'last_known_location' => 'London', 'created_by' => 'me', 'created_organisation' => 'stc')
      time = Time.local(2010, 1, 14, 14, 5, 0)
      Timecop.freeze(time) do
        base_model['last_known_location'] = 'Philadelphia'
        base_model.save!
      end
      expect(base_model['histories'].first['datetime']).to eq('2010-01-14 14:05:00UTC')
    end

    it 'should maintain history when base_model is flagged and message is added' do
      base_model = BaseModel.create('photo' => uploadable_photo, 'last_known_location' => 'London', 'created_by' => 'me', 'created_organisation' => 'stc')
      base_model['flag'] = 'true'
      base_model['flag_message'] = 'Duplicate record!'
      base_model.save!
      flag_history = base_model['histories'].first['changes']['flag']
      expect(flag_history['from']).to be_nil
      expect(flag_history['to']).to eq('true')
      flag_message_history = base_model['histories'].first['changes']['flag_message']
      expect(flag_message_history['from']).to be_nil
      expect(flag_message_history['to']).to eq('Duplicate record!')
    end

    it 'should maintain history when base_model is reunited and message is added' do
      base_model = BaseModel.create('photo' => uploadable_photo, 'last_known_location' => 'London', 'created_by' => 'me', 'created_organisation' => 'stc')
      base_model['reunited'] = 'true'
      base_model['reunited_message'] = 'Finally home!'
      base_model.save!
      reunited_history = base_model['histories'].first['changes']['reunited']
      expect(reunited_history['from']).to be_nil
      expect(reunited_history['to']).to eq('true')
      reunited_message_history = base_model['histories'].first['changes']['reunited_message']
      expect(reunited_message_history['from']).to be_nil
      expect(reunited_message_history['to']).to eq('Finally home!')
    end
  end

  describe '.without_histories' do
    it 'should not trigger add creation history' do
      base_model = nil
      BaseModel.without_histories do
        base_model = BaseModel.create('last_known_location' => 'london',
                                      'created_by' => 'me',
                                      'created_organisation' => 'stc')
      end
      expect(base_model.histories.length).to eq(0)
    end

    it 'should not trigger add history' do
      base_model = BaseModel.create('last_known_location' => 'london',
                                    'created_by' => 'me',
                                    'created_organisation' => 'stc')
      BaseModel.without_histories do
        base_model['name'] = 'new name'
        base_model.save
      end
      base_model.reload
      expect(base_model.histories.length).to eq(1)
    end
  end
end
