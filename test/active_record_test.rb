require_relative "test_helper"

class ActiveRecordTest < Minitest::Test
  def test_symmetric
    email = "test@example.org"
    User.create!(email: email)
    user = User.last
    assert_equal email, user.email
  end

  def test_rotation
    email = "test@example.org"
    key = User.lockbox_attributes[:email][:previous_versions].first[:key]
    box = Lockbox.new(key: key)
    user = User.create!(email_ciphertext: Base64.strict_encode64(box.encrypt(email)))
    user = User.last
    assert_equal email, user.email
  end

  # ensure consistent with normal attributes
  def test_dirty
    original_name = "Test"
    original_email = "test@example.org"
    new_name = "New"
    new_email = "new@example.org"

    user = User.create!(name: original_name, email: original_email)
    user = User.last
    original_email_ciphertext = user.email_ciphertext

    assert !user.name_changed?
    assert !user.email_changed?

    assert_equal original_name, user.name_was
    if ActiveRecord::VERSION::STRING >= "5.2"
      assert_nil user.email_was
    else
      assert_equal original_email, user.email_was
    end

    # update
    user.name = new_name
    user.email = new_email

    # ensure changed
    assert user.name_changed?
    assert user.email_changed?

    # ensure was
    assert_equal original_name, user.name_was
    assert_equal original_email, user.email_was

    assert_equal [original_name, new_name], user.changes["name"]
    assert_equal [original_email, new_email], user.changes["email"]

    # ensure final value
    assert_equal new_name, user.name
    assert_equal new_email, user.email
    refute_equal original_email_ciphertext, user.email_ciphertext
  end

  def test_dirty_before_last_save
    skip if Rails.version < "5.1"

    original_name = "Test"
    original_email = "test@example.org"
    new_name = "New"
    new_email = "new@example.org"

    user = User.create!(name: original_name, email: original_email)
    user = User.last

    user.update!(name: new_name, email: new_email)

    # ensure updated
    assert_equal original_name, user.name_before_last_save
    assert_equal original_email, user.email_before_last_save
  end

  def test_dirty_bad_ciphertext
    user = User.create!(email_ciphertext: "bad")
    user.email = "test@example.org"
    assert_nil user.email_was
  end

  def test_inspect
    user = User.create!(email: "test@example.org")
    assert_nil user.serializable_hash["email"]
    assert_nil user.serializable_hash["email_ciphertext"]
    refute_includes user.inspect, "email"
  end

  def test_reload
    original_email = "test@example.org"
    new_email = "new@example.org"

    user = User.create!(email: original_email)
    user.email = new_email
    assert_equal new_email, user.email
    assert_equal new_email, user.attributes["email"]

    # reload
    user.reload

    # not loaded yet
    assert_nil user.attributes["email"]

    # loaded
    assert_equal original_email, user.email
    assert_equal original_email, user.attributes["email"]
  end

  def test_nil
    user = User.create!(email: "test@example.org")
    user.email = nil
    assert_nil user.email_ciphertext
  end

  def test_empty_string
    user = User.create!(email: "test@example.org")
    user.email = ""
    assert_equal "", user.email_ciphertext
  end

  def test_hybrid
    phone = "555-555-5555"
    User.create!(phone: phone)
    user = User.last
    assert_equal phone, user.phone
  end

  def test_validations_valid
    post = Post.new(title: "Hello World")
    assert post.valid?
    post.save!
    post = Post.last
    assert post.valid?
  end

  def test_validations_presence
    post = Post.new
    assert !post.valid?
    assert_equal "Title can't be blank", post.errors.full_messages.first
  end

  def test_validations_length
    post = Post.new(title: "Hi")
    assert !post.valid?
    assert_equal "Title is too short (minimum is 3 characters)", post.errors.full_messages.first
  end

  def test_encode
    ssn = "123-45-6789"
    User.create!(ssn: ssn)
    user = User.last
    assert_equal user.ssn, ssn
    nonce_size = 12
    auth_tag_size = 16
    assert_equal nonce_size + ssn.bytesize + auth_tag_size, user.ssn_ciphertext.bytesize
  end

  def test_attribute_key_encrypted_column
    email = "test@example.org"
    user = User.create!(email: email)
    key = Lockbox.attribute_key(table: "users", attribute: "email_ciphertext")
    box = Lockbox.new(key: key)
    assert_equal email, box.decrypt(Base64.decode64(user.email_ciphertext))
  end

  def test_class_method
    email = "test@example.org"
    ciphertext = User.generate_email_ciphertext(email)
    key = Lockbox.attribute_key(table: "users", attribute: "email_ciphertext")
    box = Lockbox.new(key: key)
    assert_equal email, box.decrypt(Base64.decode64(ciphertext))
  end

  def test_type_string
    assert_attribute :country, "USA", format: "USA"
  end

  def test_type_boolean_true
    assert_attribute :active, true, format: "t"
  end

  def test_type_boolean_false
    assert_attribute :active, false, format: "f"
  end

  def test_type_boolean_bytesize
    assert_bytesize :active, true, false
  end

  def test_type_boolean_invalid
    # non-falsey values are true
    assert_attribute :active, "invalid", expected: true
  end

  def test_type_boolean_empty_string
    assert_attribute :active, "", expected: nil
  end

  def test_type_date
    dob = Date.current
    assert_attribute :dob, dob, format: dob.strftime("%Y-%m-%d")
  end

  def test_type_date_bytesize
    assert_bytesize :dob, Date.current, Date.current + 10000
    assert_bytesize :dob, Date.current, Date.current - 10000
    assert_bytesize :dob, Date.current, Date.parse("999-01-01")
    refute_bytesize :dob, Date.current, Date.parse("99999-01-01")
  end

  def test_type_date_invalid
    assert_attribute :dob, "invalid", expected: nil
  end

  def test_type_datetime
    signed_at = Time.current.round(6)
    assert_attribute :signed_at, signed_at, format: signed_at.utc.iso8601(9), time_zone: true
  end

  def test_type_datetime_bytesize
    assert_bytesize :dob, Time.current, Time.current + 100.years
    assert_bytesize :dob, Time.current, Time.current - 100.years
  end

  def test_type_datetime_invalid
    assert_attribute :signed_at, "invalid", expected: nil
  end

  def test_type_integer
    sign_in_count = 10
    assert_attribute :sign_in_count, sign_in_count, format: [sign_in_count].pack("q>")
  end

  def test_type_integer_negative
    sign_in_count = -10
    assert_attribute :sign_in_count, sign_in_count, format: [sign_in_count].pack("q>")
  end

  def test_type_integer_bytesize
    assert_bytesize :sign_in_count, 10, 1_000_000_000
    assert_bytesize :sign_in_count, -1_000_000_000, 1_000_000_000
  end

  def test_type_integer_invalid
    assert_attribute :sign_in_count, "invalid", expected: 0
    assert_attribute :sign_in_count, "55invalid", expected: 55
  end

  def test_type_integer_in_range
    value = 2**63 - 1
    assert_attribute :sign_in_count, value, expected: value

    value = -(2**63)
    assert_attribute :sign_in_count, value, expected: value
  end

  def test_type_integer_out_of_range
    assert_raises ActiveModel::RangeError do
      User.create!(sign_in_count: 2**63)
    end

    assert_raises ActiveModel::RangeError do
      User.create!(sign_in_count2: 2**63)
    end

    assert_raises ActiveModel::RangeError do
      User.create!(sign_in_count: -(2**63 + 1))
    end

    assert_raises ActiveModel::RangeError do
      User.create!(sign_in_count2: -(2**63 + 1))
    end
  end

  def test_type_float
    latitude = 10.12345678
    assert_attribute :latitude, latitude, format: [latitude].pack("G")
  end

  def test_type_float_negative
    latitude = -10.12345678
    assert_attribute :latitude, latitude, format: [latitude].pack("G")
  end

  def test_type_float_bigdecimal
    skip if ENV["ADAPTER"] == "postgresql"

    latitude = BigDecimal("123456789.123456789123456789")
    assert_attribute :latitude, latitude, expected: latitude.to_f, format: [latitude].pack("G")
  end

  def test_type_float_bytesize
    assert_bytesize :latitude, 10, 1_000_000_000.123
    assert_bytesize :latitude, -1_000_000_000.123, 1_000_000_000.123
  end

  def test_type_float_invalid
    assert_attribute :latitude, "invalid", expected: 0.0
    assert_attribute :latitude, "1.2invalid", expected: 1.2
  end

  def test_type_float_infinity
    assert_attribute :latitude, Float::INFINITY, expected: Float::INFINITY, format: [Float::INFINITY].pack("G")
    assert_attribute :latitude, -Float::INFINITY, expected: -Float::INFINITY, format: [-Float::INFINITY].pack("G")
  end

  def test_type_float_nan
    assert_attribute :latitude, Float::NAN, expected: Float::NAN, format: [Float::NAN].pack("G")
  end

  def test_type_binary
    video = SecureRandom.random_bytes(512)
    assert_attribute :video, video, format: video
  end

  def test_type_binary_bytesize
    refute_bytesize :video, SecureRandom.random_bytes(15), SecureRandom.random_bytes(16)
  end

  def test_type_json
    # json type isn't recognized with SQLite in Rails < 5.2
    skip if ActiveRecord::VERSION::STRING < "5.2"

    data = {a: 1, b: "hi"}.as_json
    assert_attribute :data, data, format: data.to_json

    user = User.last
    new_data = {c: Time.now}.as_json
    user.data = new_data
    assert_equal [data, new_data], user.changes["data"]
    user.data2 = new_data
    assert_equal [data, new_data], user.changes["data2"]
  end

  def test_type_hash
    info = {a: 1, b: "hi"}
    assert_attribute :info, info, format: info.to_yaml

    # TODO see why keys are strings instead of symbols
    user = User.last
    new_info = {c: Time.now}
    user.info = new_info
    assert_equal [info.stringify_keys, new_info.stringify_keys], user.changes["info"]
    user.info2 = new_info
    assert_equal [info.stringify_keys, new_info.stringify_keys], user.changes["info2"]
  end

  def test_type_hash_invalid
    assert_raises ActiveRecord::SerializationTypeMismatch do
      User.create!(info: "invalid")
    end

    assert_raises ActiveRecord::SerializationTypeMismatch do
      User.create!(info2: "invalid")
    end
  end

  def test_serialize_json
    properties = {a: 1, b: "hi"}.as_json
    assert_attribute :properties, properties, format: properties.to_json

    user = User.last
    new_properties = {c: Time.now}.as_json
    user.properties = new_properties
    assert_equal [properties, new_properties], user.changes["properties"]
    user.properties2 = new_properties
    assert_equal [properties, new_properties], user.changes["properties2"]
  end

  def test_serialize_json_in_place
    user = User.create!(properties2: {a: 1, b: "hi"})
    user.properties2[:c] = "world"
    user.save!
    user = User.last
    assert_equal "world", user.properties2["c"]
  end

  def test_serialize_hash
    settings = {a: 1, b: "hi"}
    assert_attribute :settings, settings, format: settings.to_yaml

    # TODO see why changes keys are strings instead of symbols
    user = User.last
    new_settings = {c: Time.now}
    user.settings = new_settings
    assert_equal [settings.stringify_keys, new_settings.stringify_keys], user.changes["settings"]
    user.settings2 = new_settings
    assert_equal [settings.stringify_keys, new_settings.stringify_keys], user.changes["settings2"]
  end

  def test_serialize_hash_in_place
    user = User.create!(settings2: {a: 1, b: "hi"})
    user.settings2[:c] = "world"
    user.save!
    user = User.last
    assert_equal "world", user.settings2[:c]
  end

  def test_serialize_hash_invalid
    assert_raises ActiveRecord::SerializationTypeMismatch do
      User.create!(settings: "invalid")
    end

    assert_raises ActiveRecord::SerializationTypeMismatch do
      User.create!(settings2: "invalid")
    end
  end

  def test_padding
    user = User.create!(city: "New York")
    assert_equal 12 + 16 + 16, Base64.decode64(user.city_ciphertext).bytesize
  end

  def test_padding_empty_string
    user = User.create!(city: "")
    assert_equal 12 + 16 + 16, Base64.decode64(user.city_ciphertext).bytesize
  end

  def test_padding_invalid
    user = User.create!(city_ciphertext: "")
    assert_raises(Lockbox::DecryptionError) do
      user.city
    end
  end

  private

  def assert_attribute(attribute, value, format: nil, time_zone: false, **options)
    attribute2 = "#{attribute}2".to_sym
    encrypted_attribute = "#{attribute2}_ciphertext"
    expected = options.key?(:expected) ? options[:expected] : value

    user = User.create!(attribute => value, attribute2 => value)
    assert_equal expected, user.send(attribute)
    assert_equal expected, user.send(attribute2)
    assert_nil user.send(encrypted_attribute) if expected.nil?

    # encoding
    if expected.is_a?(String)
      assert_equal expected.encoding, user.send(attribute).encoding
      assert_equal expected.encoding, user.send(attribute2).encoding
    end

    # time zone
    if time_zone
      assert_equal Time.zone, user.send(attribute).time_zone
      assert_equal Time.zone, user.send(attribute2).time_zone
    end

    user = User.last
    # SQLite does not support NaN
    assert_equal expected, user.send(attribute) unless expected.try(:nan?) && !ENV["ADAPTER"]
    assert_equal expected, user.send(attribute2)

    # encoding
    if expected.is_a?(String)
      assert_equal expected.encoding, user.send(attribute).encoding
      assert_equal expected.encoding, user.send(attribute2).encoding
    end

    # time zone
    if time_zone
      assert_equal Time.zone, user.send(attribute).time_zone
      assert_equal Time.zone, user.send(attribute2).time_zone
    end

    if format
      key = Lockbox.attribute_key(table: "users", attribute: encrypted_attribute)
      box = Lockbox.new(key: key)
      assert_equal format, box.decrypt(Base64.decode64(user.send(encrypted_attribute)))
    end

    user.send("#{attribute2}=", nil)
    assert_nil user.send(encrypted_attribute)
  end

  def assert_equal(exp, act)
    if exp.try(:nan?)
      assert act.try(:nan?), "Expected NaN"
    elsif exp.nil?
      assert_nil act
    else
      super
    end
  end

  def assert_bytesize(*args)
    assert_equal *bytesizes(*args)
  end

  def refute_bytesize(*args)
    refute_equal *bytesizes(*args)
  end

  def bytesizes(attribute, value1, value2)
    attribute = "#{attribute}2".to_sym
    encrypted_attribute = "#{attribute}_ciphertext"
    user1 = User.create!(attribute => value1)
    user2 = User.create!(attribute => value2)
    result1 = Base64.decode64(user1.send(encrypted_attribute)).bytesize
    result2 = Base64.decode64(user2.send(encrypted_attribute)).bytesize
    [result1, result2]
  end
end