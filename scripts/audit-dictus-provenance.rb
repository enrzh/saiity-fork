# Inventory source ancestry; a changed file or missing path is not proof of independent authorship.
require "digest"
require "json"
require "open3"

def git(*arguments)
  output, error, result = Open3.capture3("git", *arguments)
  raise error unless result.success?
  output
end

def ancestry(original, current)
  return "unchanged" if original.b == current.b
  if original.dup.force_encoding("UTF-8").valid_encoding? && current.dup.force_encoding("UTF-8").valid_encoding?
    return "module_name_only" if original.gsub("DictusCore", "SyllivraKernel").b == current.b
  end
  "modified_requires_review"
end

if ARGV == ["--self-test"]
  raise "identity" unless ancestry("same", "same") == "unchanged"
  raise "module rename" unless ancestry("import DictusCore\n", "import SyllivraKernel\n") == "module_name_only"
  raise "changed source" unless ancestry("first", "second") == "modified_requires_review"
  raise "binary identity" unless ancestry("\xff".b, "\xff".b) == "unchanged"
  raise "binary change" unless ancestry("\xff".b, "\xfe".b) == "modified_requires_review"
  puts "PASS: source, module-only and binary ancestry checks"
  exit
end
abort "Usage: ruby scripts/audit-dictus-provenance.rb [--self-test]" unless ARGV.empty?

baseline = "69bb19af6657e9ba0be5880ef70fab3bd25e4671"
original_paths = git("ls-tree", "-r", "--name-only", "-z", baseline).split("\0")
scopes = ["DictusApp", "DictusKeyboard", "DictusWidgets", "Dictus/Sounds", "SyllivraKernel/Sources"]
current_paths = git("ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *scopes).split("\0").uniq.sort
original_hashes = {}
original_paths.each do |path|
  next unless path.start_with?("DictusApp/", "DictusKeyboard/", "DictusWidgets/", "Dictus/Sounds/", "DictusCore/Sources/")
  digest = Digest::SHA256.hexdigest(git("show", "#{baseline}:#{path}"))
  (original_hashes[digest] ||= []) << path
end

files = current_paths.map do |path|
  next unless File.file?(path)
  contents = File.binread(path)
  digest = Digest::SHA256.hexdigest(contents)
  original_path = path.sub("SyllivraKernel/Sources/SyllivraKernel/", "DictusCore/Sources/DictusCore/")
                      .sub("SyllivraKernel/Sources/SyllivraInference/", "DictusCore/Sources/DictusInference/")
  original_path = original_hashes[digest]&.first unless original_paths.include?(original_path)
  {
    path: path, sha256: digest, bytes: contents.bytesize, upstream_path: original_path,
    ancestry: original_path ? ancestry(git("show", "#{baseline}:#{original_path}"), contents) : "no_matching_origin_path"
  }
end.compact

puts JSON.pretty_generate({
  baseline: baseline,
  head: git("rev-parse", "HEAD").strip,
  limitation: "Inventory only. Modified/new paths, low text overlap and renamed symbols do not establish independent authorship or license clearance.",
  counts: files.group_by { |file| file.fetch(:ancestry) }.transform_values(&:length),
  files: files
})
