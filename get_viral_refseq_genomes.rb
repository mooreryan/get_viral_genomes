#!/usr/bin/env ruby
Signal.trap("PIPE", "EXIT")

# Number of files that viral refseq is split into
VIRAL_REFSEQ_SPLITS = 2

# Scripts
PARSE_VIRAL_REFSEQ_HOST = File.join(__dir__, "viral_refseq_host_and_type.rb")

require "aai"
require "abort_if"
require "trollop"
require "fileutils"
require "parallel"

include AbortIf

Time.extend Aai::CoreExtensions::Time
Process.extend Aai::CoreExtensions::Process

opts = Trollop.options do
  banner <<-EOS

  Info

  Options:
  EOS

  opt(:directory,
      "Base directory where the genomes will live (date will be appended)",
      type: :string,
      default: "viral_genomes")
  opt(:cpus,
      "Number of cpus",
      default: 4)
end

cur_date = Time.now.strftime "%Y_%m_%d"
dir_base = "#{opts[:directory]}_#{cur_date}"
dir_viral_refseq = File.join(dir_base, "refseq_viral")
viral_refseq_readme = File.join dir_viral_refseq, "README"


FileUtils.mkdir_p dir_base
FileUtils.mkdir_p dir_viral_refseq

# Get Viral RefSeq genomes




Parallel.each((VIRAL_REFSEQ_SPLITS * 2).times, in_processes: opts[:cpus]) do |idx|
  num = (idx % VIRAL_REFSEQ_SPLITS) + 1 # viral refseq counts from 1

  if idx >= VIRAL_REFSEQ_SPLITS
    # Then the gbff to parse for host names and such.
    gbff_fname = "viral.#{num}.genomic.gbff.gz"
    gbff_outf = File.join dir_viral_refseq, "viral.#{num}.genomic.gbff"
    url = "ftp://ftp.ncbi.nlm.nih.gov/refseq/release/viral/#{gbff_fname}"

    # Needs to be unzipped for BioRuby to parse it.
    cmd = "\\curl --silent #{url} | gunzip -c > #{gbff_outf}"
    Process.run_and_time_it! "Downloading gbff #{gbff_fname}", cmd
  else
    # And get the gpff files
    gpff_fname = "viral.#{num}.protein.gpff.gz"
    gpff_outf = File.join dir_viral_refseq, "viral.#{num}.protein.gpff"
    url = "ftp://ftp.ncbi.nlm.nih.gov/refseq/release/viral/#{gpff_fname}"

    # Needs to be unzipped for BioRuby to parse it.
    cmd = "\\curl --silent #{url} | gunzip -c > #{gpff_outf}"
    Process.run_and_time_it! "Downloading gpff #{gpff_fname}", cmd
  end
end

# Make the single gb outf
gbff_outfs = File.join dir_viral_refseq, "viral.*.genomic.gbff"
new_gbff_outf = File.join dir_viral_refseq, "viral.genomic.gbff"
cmd = "cat #{gbff_outfs} > #{new_gbff_outf}"
Process.run_and_time_it! "Catting gbff files", cmd

# Make the single gp outf
gpff_outfs = File.join dir_viral_refseq, "viral.*.protein.gpff"
new_gpff_outf = File.join dir_viral_refseq, "viral.protein.gpff"
cmd = "cat #{gpff_outfs} > #{new_gpff_outf}"
Process.run_and_time_it! "Catting gpff files", cmd

Parallel.each(2.times, in_processes: 2) do |idx|
  if idx.zero?
    # Now parse the gb file.
    cmd = "ruby #{PARSE_VIRAL_REFSEQ_HOST} #{new_gbff_outf}"
    Process.run_and_time_it! "Getting hosts and seqs", cmd

    # Remove the gb file.
    Process.run_and_time_it! "Removing temp gbff files", "rm #{File.join(dir_viral_refseq, '*.gbff')}"
  else
    # Parse the gp file
    cmd = "ruby #{File.join(__dir__, viral_refseq_protein.rb)} #{new_gpff_outf}"
    Process.run_and_time_it! "Processing protein files", cmd

    # Remove the gp file.
    Process.run_and_time_it! "Removing gpff files", "rm #{File.join(dir_viral_refseq, '*.gpff')}"
  end
end

# Link up hosts with proteins.
host_info = {}
host_fname = File.join(dir_viral_refseq, "viral.genomic.hosts.txt")
File.open(host_fname, "rt").each_line do |line|
  gen_acc, _, _, *hosts = line.chomp.split "\t"

  host_info[gen_acc] = hosts.join "\t"
end

protein_info_fname = File.join(dir_viral_refseq, "viral.protein.info.txt")
protein_hosts_fname = File.join(dir_viral_refseq, "viral.protein_with_hosts.info.txt")
File.open(protein_hosts_fname, "w") do |f|
  File.open(protein_info_fname).each_line do |line|
    line.chomp!

    ary = line.split "\t"
    gen_acc = ary[1]

    if host_info.has_key? gen_acc
      f.puts [line, host_info[gen_acc]].join "\t"
    else
      f.puts [line, ""].join "\t"
    end
  end
end

# Write any READMEs

File.open(viral_refseq_readme, "w") do |f|
  f.puts %Q{
The *.hosts.txt file only has entries for those entries in viral refseq that have host info.  I.e. those that have source => host or source => lab_host.
}
end
