class Dependency < ActiveRecord::Base
  belongs_to :rubygem
  belongs_to :version

  before_validation :use_gem_dependency,
                    :use_existing_rubygem,
                    :parse_gem_dependency
  after_create      :push_on_to_list

  validates_presence_of  :requirements
  validates_inclusion_of :scope, :in => %w( development runtime )

  scope :development, where(:scope => 'development')
  scope :runtime,     where(:scope => 'runtime')

  attr_accessor :gem_dependency

  LIMIT = 250

  def name
    rubygem.name
  end

  def payload
    {
      'name'         => name,
      'requirements' => requirements
    }
  end

  def as_json(options = {})
    payload
  end

  def to_xml(options = {})
    payload.to_xml(options.merge(:root => "dependency"))
  end

  def to_s
    "#{name} #{requirements}"
  end

  def self.runtime_key(full_name)
    "rd:#{full_name}"
  end

  # rails,rack,bundler
  def self.for(gem_list)
    gem_list.map do |rubygem_name|
      versions = $redis.lrange(Rubygem.versions_key(rubygem_name), 0, -1)
      versions.map do |version|
        info = $redis.hgetall(Version.info_key(version))
        deps = $redis.lrange(Dependency.runtime_key(version), 0, -1)
        {
          :name         => info["name"],
          :number       => info["number"],
          :platform     => info["platform"],
          :dependencies => deps.map { |dep| dep.split(" ", 2) }
        }
      end
    end.flatten
  end

  private

  def use_gem_dependency
    if gem_dependency.class != Gem::Dependency
      errors.add :rubygem, "Please use Gem::Dependency to specify dependencies." 
      false
    end
  end

  def use_existing_rubygem
    self.rubygem = Rubygem.find_by_name(gem_dependency.name)

    if rubygem.blank?
      errors[:base] << "Please specify dependencies that exist on #{I18n.t(:title)}: #{gem_dependency}"
      false
    end
  end

  def parse_gem_dependency
    self.requirements = gem_dependency.requirements_list.join(', ')
    self.scope = gem_dependency.type.to_s
  end

  def push_on_to_list
    $redis.lpush(Dependency.runtime_key(self.version.full_name), self.to_s)
  end
end
